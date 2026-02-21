"""Shared overlay store — Redis Vector Search backend.

Publishes overlays to Redis so other Bones sessions can discover them.
Uses Voyage AI embeddings (via httpx) for semantic similarity search.

Redis Stack required: localhost:6379 with RediSearch + RedisJSON modules.
"""

import json
import time
import os

# Lazy imports — only loaded when a Redis tool is actually called
_redis = None
_httpx = None


def _get_redis():
    global _redis
    if _redis is None:
        import redis
        _redis = redis
    return _redis


def _get_httpx():
    global _httpx
    if _httpx is None:
        import httpx
        _httpx = httpx
    return _httpx


def _log(text: str):
    import sys
    sys.stderr.write(f"[redis_store] {text}\n")
    sys.stderr.flush()


# ---------------------------------------------------------------------------
# Embeddings via Voyage API (uses httpx, no extra deps)
# ---------------------------------------------------------------------------

VOYAGE_MODEL = "voyage-3-lite"
EMBEDDING_DIMS = 512
VOYAGE_API_URL = "https://api.voyageai.com/v1/embeddings"


def _embed_text(text: str, api_key: str) -> list[float]:
    """Get embedding vector from Voyage AI API."""
    httpx = _get_httpx()
    resp = httpx.post(
        VOYAGE_API_URL,
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
        json={
            "model": VOYAGE_MODEL,
            "input": [text],
            "input_type": "document",
        },
        timeout=30.0,
    )
    resp.raise_for_status()
    data = resp.json()
    return data["data"][0]["embedding"]


def _embed_query(text: str, api_key: str) -> list[float]:
    """Get query embedding (uses input_type=query for better retrieval)."""
    httpx = _get_httpx()
    resp = httpx.post(
        VOYAGE_API_URL,
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
        json={
            "model": VOYAGE_MODEL,
            "input": [text],
            "input_type": "query",
        },
        timeout=30.0,
    )
    resp.raise_for_status()
    data = resp.json()
    return data["data"][0]["embedding"]


def _embed_text_string(name: str, description: str, domain: str, tags: list[str]) -> str:
    """Build the text string we embed for an overlay."""
    tag_str = ", ".join(tags) if tags else ""
    return f"{name}. {description}. domain:{domain}. {tag_str}"


# ---------------------------------------------------------------------------
# SharedOverlayStore
# ---------------------------------------------------------------------------

INDEX_NAME = "idx:overlays"
KEY_PREFIX = "bones:overlay:"


class SharedOverlayStore:
    """Redis-backed shared overlay store with vector search."""

    def __init__(self, api_key: str | None = None):
        self._client = None
        self._index_checked = False
        self._api_key = api_key  # Anthropic API key — also works as Voyage key if set
        self._voyage_key = os.environ.get("VOYAGE_API_KEY") or api_key

    def _connect(self):
        """Lazy connect to Redis."""
        if self._client is not None:
            return self._client
        redis = _get_redis()
        try:
            self._client = redis.Redis(host="localhost", port=6379, decode_responses=True)
            self._client.ping()
            _log("connected to Redis")
        except Exception as e:
            _log(f"Redis connection failed: {e}")
            self._client = None
            raise
        return self._client

    def _ensure_index(self):
        """Create RediSearch index if it doesn't exist."""
        if self._index_checked:
            return
        r = self._connect()
        try:
            r.execute_command("FT.INFO", INDEX_NAME)
            _log("index already exists")
        except Exception:
            # Create the index
            _log("creating RediSearch index")
            import struct
            r.execute_command(
                "FT.CREATE", INDEX_NAME,
                "ON", "JSON",
                "PREFIX", "1", KEY_PREFIX,
                "SCHEMA",
                "$.domain", "AS", "domain", "TAG",
                "$.name", "AS", "name", "TEXT", "WEIGHT", "2.0",
                "$.description", "AS", "description", "TEXT",
                "$.tags[*]", "AS", "tags", "TAG",
                "$.embedding", "AS", "embedding", "VECTOR",
                "FLAT", "6",
                "TYPE", "FLOAT32",
                "DIM", str(EMBEDDING_DIMS),
                "DISTANCE_METRIC", "COSINE",
            )
            _log("index created")
        self._index_checked = True

    def publish(self, overlay: dict, domain: str, tags: list[str] | None = None) -> str:
        """Publish an overlay to Redis.

        Args:
            overlay: dict with id, name, description, html, width, height, position
            domain: e.g. "github.com"
            tags: optional list of tags

        Returns:
            Redis key
        """
        self._ensure_index()
        r = self._connect()
        tags = tags or []
        overlay_id = overlay["id"]
        key = f"{KEY_PREFIX}{domain}:{overlay_id}"

        # Build embed text and get embedding
        embed_text = _embed_text_string(
            overlay["name"], overlay.get("description", ""), domain, tags
        )
        try:
            embedding = _embed_text(embed_text, self._voyage_key)
        except Exception as e:
            _log(f"embedding failed, publishing without vector: {e}")
            embedding = [0.0] * EMBEDDING_DIMS

        doc = {
            "id": overlay_id,
            "name": overlay["name"],
            "description": overlay.get("description", ""),
            "domain": domain,
            "html": overlay["html"],
            "width": overlay.get("width", 400),
            "height": overlay.get("height", 300),
            "position": overlay.get("position", "top-right"),
            "tags": tags,
            "created_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "embedding": embedding,
        }

        r.execute_command("JSON.SET", key, "$", json.dumps(doc))
        _log(f"published {key}")
        return key

    def search_exact(self, domain: str, limit: int = 10) -> list[dict]:
        """Find overlays for an exact domain match."""
        self._ensure_index()
        r = self._connect()
        query = f"@domain:{{{_escape_tag(domain)}}}"
        try:
            results = r.execute_command(
                "FT.SEARCH", INDEX_NAME, query,
                "RETURN", "5", "$.id", "$.name", "$.description", "$.domain", "$.position",
                "LIMIT", "0", str(limit),
            )
            return _parse_search_results(results)
        except Exception as e:
            _log(f"exact search failed: {e}")
            return []

    def search_similar(self, query_text: str, exclude_domain: str | None = None, limit: int = 5) -> list[dict]:
        """Semantic similarity search across all overlays."""
        self._ensure_index()
        r = self._connect()

        try:
            embedding = _embed_query(query_text, self._voyage_key)
        except Exception as e:
            _log(f"query embedding failed: {e}")
            return []

        import struct
        blob = struct.pack(f"{EMBEDDING_DIMS}f", *embedding)

        # KNN search, optionally excluding a domain
        if exclude_domain:
            filter_q = f"-@domain:{{{_escape_tag(exclude_domain)}}}"
            ft_query = f"({filter_q})=>[KNN {limit} @embedding $vec AS score]"
        else:
            ft_query = f"*=>[KNN {limit} @embedding $vec AS score]"

        try:
            results = r.execute_command(
                "FT.SEARCH", INDEX_NAME, ft_query,
                "PARAMS", "2", "vec", blob,
                "RETURN", "6", "$.id", "$.name", "$.description", "$.domain", "$.position", "score",
                "SORTBY", "score",
                "LIMIT", "0", str(limit),
                "DIALECT", "2",
            )
            return _parse_search_results(results)
        except Exception as e:
            _log(f"similar search failed: {e}")
            return []

    def get_overlay(self, key: str) -> dict | None:
        """Fetch a full overlay document from Redis by key."""
        r = self._connect()
        try:
            raw = r.execute_command("JSON.GET", key, "$")
            if raw:
                docs = json.loads(raw)
                if docs and len(docs) > 0:
                    return docs[0]
        except Exception as e:
            _log(f"get_overlay failed: {e}")
        return None

    def is_available(self) -> bool:
        """Check if Redis is reachable."""
        try:
            self._connect()
            return True
        except Exception:
            return False


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _escape_tag(value: str) -> str:
    """Escape special characters for RediSearch TAG queries."""
    # TAG values need certain chars escaped
    special = r",./<>{}[]\"':;!@#$%^&*()-+=~"
    result = ""
    for ch in value:
        if ch in special:
            result += "\\" + ch
        else:
            result += ch
    return result


def _parse_search_results(results) -> list[dict]:
    """Parse FT.SEARCH results into list of dicts."""
    if not results or results[0] == 0:
        return []
    parsed = []
    # results format: [total_count, key1, [field, val, ...], key2, [...], ...]
    i = 1
    while i < len(results):
        key = results[i]
        fields = results[i + 1] if i + 1 < len(results) else []
        doc = {"_key": key}
        # fields is a flat list of [name, value, name, value, ...]
        j = 0
        while j < len(fields) - 1:
            fname = fields[j]
            fval = fields[j + 1]
            # Strip $. prefix from field names
            clean_name = fname.replace("$.", "") if isinstance(fname, str) else fname
            # Parse JSON arrays/strings
            if isinstance(fval, str):
                try:
                    fval = json.loads(fval)
                except (json.JSONDecodeError, TypeError):
                    pass
            doc[clean_name] = fval
            j += 2
        parsed.append(doc)
        i += 2
    return parsed
