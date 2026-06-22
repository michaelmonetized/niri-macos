import Foundation
import AppKit

/// Unix domain socket IPC server for external control
public class IPCServer {
    public static let shared = IPCServer()
    
    private let logger = Logger.shared
    public var socketPath: String = Constants.defaultSocketPath
    private var serverSocket: Int32 = -1
    private var isRunning = false
    private var clientHandlers: [Int32: Thread] = [:]
    
    private init() {}
    
    // MARK: - Server Lifecycle
    
    public func start() {
        guard !isRunning else { return }
        
        // Remove existing socket file
        unlink(socketPath)
        
        // Create socket
        serverSocket = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverSocket >= 0 else {
            logger.error("Failed to create socket: \(errno)")
            return
        }
        
        // Bind to path
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            socketPath.withCString { cstr in
                _ = strcpy(UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self), cstr)
            }
        }
        
        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(serverSocket, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        
        guard bindResult == 0 else {
            logger.error("Failed to bind socket: \(errno)")
            close(serverSocket)
            return
        }
        
        // Listen
        guard Darwin.listen(serverSocket, 5) == 0 else {
            logger.error("Failed to listen on socket: \(errno)")
            close(serverSocket)
            return
        }
        
        isRunning = true
        logger.info("IPC server listening on \(socketPath)")
        
        // Accept connections in background
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.acceptLoop()
        }
    }
    
    public func stop() {
        isRunning = false
        
        if serverSocket >= 0 {
            close(serverSocket)
            serverSocket = -1
        }
        
        unlink(socketPath)
        logger.info("IPC server stopped")
    }
    
    // MARK: - Connection Handling
    
    private func acceptLoop() {
        while isRunning {
            var clientAddr = sockaddr_un()
            var clientAddrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
            
            let clientSocket = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    accept(serverSocket, sockPtr, &clientAddrLen)
                }
            }
            
            if clientSocket < 0 {
                if isRunning {
                    logger.error("Accept failed: \(errno)")
                }
                continue
            }
            
            logger.debug("Client connected: \(clientSocket)")
            
            // Handle client in separate thread
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.handleClient(clientSocket)
            }
        }
    }
    
    private func handleClient(_ socket: Int32) {
        defer {
            close(socket)
            logger.debug("Client disconnected: \(socket)")
        }
        
        // Read request
        var buffer = [CChar](repeating: 0, count: Constants.socketBufferSize)
        let bytesRead = read(socket, &buffer, buffer.count - 1)
        
        guard bytesRead > 0 else {
            return
        }
        
        buffer[bytesRead] = 0
        let requestString = String(cString: buffer)
        
        // Process request on main thread (LayoutEngine is main-thread-only)
        var response = ""
        DispatchQueue.main.sync {
            response = self.processRequest(requestString)
        }

        // Send response
        let responseData = response.data(using: .utf8) ?? Data()
        _ = responseData.withUnsafeBytes { ptr in
            write(socket, ptr.baseAddress, responseData.count)
        }
    }
    
    // MARK: - Request Processing
    
    private func processRequest(_ requestString: String) -> String {
        logger.debug("IPC request: \(requestString.trimmingCharacters(in: .whitespacesAndNewlines))")
        
        // Parse JSON request
        guard let data = requestString.data(using: .utf8),
              let request = try? JSONDecoder().decode(IPCRequest.self, from: data) else {
            return encodeResponse(IPCResponse(success: false, error: "Invalid request format", data: nil))
        }
        
        // Execute command
        let response = executeCommand(request)
        return encodeResponse(response)
    }
    
    private func executeCommand(_ request: IPCRequest) -> IPCResponse {
        guard let command = IPCCommand(rawValue: request.command) else {
            return IPCResponse(success: false, error: "Unknown command: \(request.command)", data: nil)
        }
        
        let engine = LayoutEngine.shared
        
        switch command {
        case .focusColumnLeft:
            engine.focusColumnLeft()
        case .focusColumnRight:
            engine.focusColumnRight()
        case .focusColumnFirst:
            engine.focusColumnFirst()
        case .focusColumnLast:
            engine.focusColumnLast()
        case .focusWindowUp:
            engine.focusWindowUp()
        case .focusWindowDown:
            engine.focusWindowDown()
            
        case .moveColumnLeft:
            engine.moveColumnLeft()
        case .moveColumnRight:
            engine.moveColumnRight()
        case .moveWindowUp:
            engine.moveWindowUp()
        case .moveWindowDown:
            engine.moveWindowDown()
            
        case .consumeWindow:
            engine.consumeWindowIntoColumn()
        case .expelWindow:
            engine.expelWindowFromColumn()
            
        case .centerColumn:
            engine.centerColumn()
        case .maximizeColumn:
            engine.maximizeColumn()
        case .switchPresetWidth:
            engine.switchPresetColumnWidth()
        case .setColumnWidth:
            if let widthSpec = request.args?["width"] ?? request.args?["arg0"] {
                engine.setColumnWidth(widthSpec)
            } else {
                return IPCResponse(success: false, error: "Missing width argument", data: nil)
            }
            
        case .scrollWorkspace:
            if let deltaStr = request.args?["delta"] ?? request.args?["arg0"],
               let delta = Double(deltaStr) {
                engine.scroll(by: CGFloat(delta))
            } else {
                return IPCResponse(success: false, error: "Missing or invalid delta argument", data: nil)
            }
            
        case .focusWorkspace:
            if let wsStr = request.args?["workspace"] ?? request.args?["arg0"],
               let wsIndex = Int(wsStr) {
                engine.focusWorkspace(wsIndex)
            } else {
                return IPCResponse(success: false, error: "Missing workspace index", data: nil)
            }
        case .moveToWorkspace:
            if let wsStr = request.args?["workspace"] ?? request.args?["arg0"],
               let wsIndex = Int(wsStr) {
                engine.moveWindowToWorkspace(wsIndex)
            } else {
                return IPCResponse(success: false, error: "Missing workspace index", data: nil)
            }
        case .workspaceUp:
            logger.info("IPC: workspace-up")
            engine.workspaceUp()
        case .workspaceDown:
            logger.info("IPC: workspace-down")
            engine.workspaceDown()
        case .createWorkspaceAbove:
            logger.info("IPC: create-workspace-above triggered!")
            engine.createWorkspaceAbove()
        case .createWorkspaceBelow:
            logger.info("IPC: create-workspace-below triggered!")
            engine.createWorkspaceBelow()
            
        case .toggleFullscreen:
            engine.toggleFullscreen()
            
        // Split groups
        case .createSplitHorizontal:
            engine.createSplitGroup(.horizontal)
        case .createSplitVertical:
            engine.createSplitGroup(.vertical)
        case .createSplitQuad:
            engine.createSplitGroup(.quad)
            
        case .listWindows:
            let windows = engine.listWindows()
            // Convert to simple string dict for JSON encoding
            var data: [String: String] = [:]
            for (i, window) in windows.enumerated() {
                let id = window["id"] as? UInt32 ?? 0
                let app = window["app"] as? String ?? "?"
                let title = window["title"] as? String ?? ""
                let focused = window["focused"] as? Bool ?? false
                let col = window["column"] as? Int ?? 0
                data["window_\(i)"] = "\(id): [\(col)] \(app) - \(title)\(focused ? " *" : "")"
            }
            return IPCResponse(success: true, error: nil, data: data)
            
        case .status:
            let status = engine.getStatus()
            var data: [String: String] = [:]
            for (key, value) in status {
                data[key] = "\(value)"
            }
            return IPCResponse(success: true, error: nil, data: data)
            
        case .quit:
            DispatchQueue.main.async {
                NSApplication.shared.terminate(nil)
            }
        }
        
        return IPCResponse(success: true, error: nil, data: nil)
    }
    
    private func encodeResponse(_ response: IPCResponse) -> String {
        guard let data = try? JSONEncoder().encode(response),
              let string = String(data: data, encoding: .utf8) else {
            return "{\"success\":false,\"error\":\"Encoding error\"}"
        }
        return string
    }
}
