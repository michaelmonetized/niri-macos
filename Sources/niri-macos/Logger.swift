import Foundation

class Logger {
    static let shared = Logger()
    private let logPath = "/tmp/niri-macos.log"
    private let dateFormatter: DateFormatter
    private let fileHandle: FileHandle?
    
    private init() {
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        
        // Create or truncate log file
        FileManager.default.createFile(atPath: logPath, contents: nil)
        fileHandle = FileHandle(forWritingAtPath: logPath)
    }
    
    deinit {
        try? fileHandle?.close()
    }
    
    func log(_ message: String, level: String = "INFO") {
        let timestamp = dateFormatter.string(from: Date())
        let line = "[\(timestamp)] [\(level)] \(message)\n"
        
        // Write to file
        if let data = line.data(using: .utf8) {
            fileHandle?.write(data)
            try? fileHandle?.synchronize()
        }
        
        // Also print to console
        print(line, terminator: "")
    }
    
    func info(_ message: String) {
        log(message, level: "INFO")
    }
    
    func error(_ message: String) {
        log(message, level: "ERROR")
    }
    
    func debug(_ message: String) {
        log(message, level: "DEBUG")
    }
}
