import Foundation

public enum LogLevel: Int, Comparable {
    case debug = 0
    case info = 1
    case error = 2

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public class Logger: Logging {
    public static let shared = Logger()
    private let logPath: String
    private let dateFormatter: DateFormatter
    private let fileHandle: FileHandle?
    private let lock = NSLock()
    private var pendingWrites = 0
    private let flushInterval = 50

    public var minimumLevel: LogLevel = .info

    private init() {
        logPath = Constants.defaultLogPath
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

        // Create or truncate log file
        FileManager.default.createFile(atPath: logPath, contents: nil)
        fileHandle = FileHandle(forWritingAtPath: logPath)
    }

    deinit {
        try? fileHandle?.close()
    }

    public func log(_ message: String, level: LogLevel) {
        guard level >= minimumLevel else { return }

        let levelStr: String
        switch level {
        case .debug: levelStr = "DEBUG"
        case .info: levelStr = "INFO"
        case .error: levelStr = "ERROR"
        }

        lock.lock()
        let timestamp = dateFormatter.string(from: Date())
        let line = "[\(timestamp)] [\(levelStr)] \(message)\n"

        if let data = line.data(using: .utf8) {
            fileHandle?.write(data)
            pendingWrites += 1
            // Flush on errors or periodically (not every line)
            if level == .error || pendingWrites >= flushInterval {
                try? fileHandle?.synchronize()
                pendingWrites = 0
            }
        }
        lock.unlock()

        print(line, terminator: "")
    }

    public func info(_ message: String) {
        log(message, level: .info)
    }

    public func error(_ message: String) {
        log(message, level: .error)
    }

    public func debug(_ message: String) {
        log(message, level: .debug)
    }
}
