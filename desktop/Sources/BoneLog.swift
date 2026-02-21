import Foundation

/// Simple file-based logger for debugging.
/// Writes to ~/Desktop/bones-debug.log so it's easy to find and tail.
enum BoneLog {
    private static let logURL: URL = {
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        return desktop.appendingPathComponent("bones-debug.log")
    }()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private static var fileHandle: FileHandle? = {
        // Create or truncate on app start
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        return try? FileHandle(forWritingTo: logURL)
    }()

    static func log(_ message: String) {
        let timestamp = dateFormatter.string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        if let data = line.data(using: .utf8) {
            fileHandle?.seekToEndOfFile()
            fileHandle?.write(data)
        }
    }
}
