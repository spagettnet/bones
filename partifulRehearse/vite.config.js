import { defineConfig } from 'vite';

function anthropicProxy() {
  return {
    name: 'anthropic-proxy',
    configureServer(server) {
      server.middlewares.use('/api/chat', async (req, res) => {
        if (req.method !== 'POST') {
          res.writeHead(405);
          res.end('Method not allowed');
          return;
        }

        const chunks = [];
        for await (const chunk of req) chunks.push(chunk);
        const body = JSON.parse(Buffer.concat(chunks).toString());

        const { apiKey, system, messages, stream = true, max_tokens = 128 } = body;

        try {
          const upstream = await fetch('https://api.anthropic.com/v1/messages', {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              'x-api-key': apiKey,
              'anthropic-version': '2023-06-01',
            },
            body: JSON.stringify({
              model: 'claude-sonnet-4-20250514',
              max_tokens,
              stream,
              system,
              messages,
            }),
          });

          if (!upstream.ok) {
            const errText = await upstream.text();
            res.writeHead(upstream.status, { 'Content-Type': 'text/plain' });
            res.end(errText);
            return;
          }

          if (!stream) {
            const json = await upstream.text();
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(json);
            return;
          }

          res.writeHead(200, {
            'Content-Type': 'text/event-stream',
            'Cache-Control': 'no-cache',
            'Connection': 'keep-alive',
          });

          const reader = upstream.body.getReader();
          while (true) {
            const { done, value } = await reader.read();
            if (done) break;
            res.write(value);
          }
          res.end();
        } catch (err) {
          res.writeHead(500, { 'Content-Type': 'text/plain' });
          res.end(err.message);
        }
      });
    },
  };
}

export default defineConfig({
  root: '.',
  publicDir: 'public',
  plugins: [anthropicProxy()],
});
