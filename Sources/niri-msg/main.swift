import Foundation

/// CLI tool for sending commands to niri-macos
struct NiriMsg {
    static var socketPath = "/tmp/niri-macos.sock"

    static let usage = """
    niri-msg - Control niri-macos window manager

    Usage: niri-msg <command> [args]

    Navigation:
      focus-column-left         Move focus to the left column
      focus-column-right        Move focus to the right column
      focus-column-first        Move focus to the first column
      focus-column-last         Move focus to the last column
      focus-window-up           Move focus up within column
      focus-window-down         Move focus down within column

    Movement:
      move-column-left          Move focused column left
      move-column-right         Move focused column right
      move-window-up            Move focused window up in column
      move-window-down          Move focused window down in column

    Column Operations:
      consume-window-into-column    Merge next window into current column
      expel-window-from-column      Split focused window to new column

    Size:
      switch-preset-column-width    Cycle through width presets (33%, 50%, 66%, 100%)
      set-column-width <spec>       Set column width (e.g., "50%", "+10%", "-50", "800")
      center-column                 Center the focused column on screen
      maximize-column               Maximize column to full width
      toggle-fullscreen             Toggle between maximized and default width

    Scroll:
      scroll-workspace <delta>      Scroll viewport by delta pixels (+ = right, - = left)

    Workspace:
      focus-workspace <n>           Switch to workspace n (1-indexed)
      move-window-to-workspace <n>  Move focused window to workspace n
      workspace-up                  Switch to previous workspace
      workspace-down                Switch to next workspace (creates if needed)

    Debug:
      list-windows                  List all managed windows
      status                        Show current layout status

    Other:
      quit                          Quit niri-macos daemon
      help                          Show this help message

    Examples:
      niri-msg focus-column-right
      niri-msg set-column-width 50%
      niri-msg set-column-width +10%
      niri-msg scroll-workspace -200
      niri-msg focus-workspace 2
      niri-msg list-windows

    skhd config example:
      alt - h : niri-msg focus-column-left
      alt - l : niri-msg focus-column-right
      alt - j : niri-msg focus-window-down
      alt - k : niri-msg focus-window-up
      shift + alt - h : niri-msg move-column-left
      shift + alt - l : niri-msg move-column-right
      shift + alt - j : niri-msg move-window-down
      shift + alt - k : niri-msg move-window-up
      alt - w : niri-msg switch-preset-column-width
      alt - c : niri-msg center-column
      alt - f : niri-msg toggle-fullscreen
      ctrl + alt - h : niri-msg consume-window-into-column
      ctrl + alt - l : niri-msg expel-window-from-column
      alt - 1 : niri-msg focus-workspace 1
      alt - 2 : niri-msg focus-workspace 2
      shift + alt - 1 : niri-msg move-window-to-workspace 1
      shift + alt - 2 : niri-msg move-window-to-workspace 2
    """
    
    static func main() {
        var args = Array(CommandLine.arguments.dropFirst())

        // Parse --socket flag before command processing
        if let idx = args.firstIndex(of: "--socket") ?? args.firstIndex(of: "-s"),
           idx + 1 < args.count {
            socketPath = args[idx + 1]
            args.removeSubrange(idx...idx+1)
        }

        guard !args.isEmpty else {
            print(usage)
            exit(0)
        }

        let command = args[0]

        if command == "help" || command == "--help" || command == "-h" {
            print(usage)
            exit(0)
        }

        // Build request
        var request: [String: Any] = ["command": command]

        // Handle commands with arguments
        if args.count > 1 {
            var cmdArgs: [String: String] = [:]

            switch command {
            case "scroll-workspace":
                cmdArgs["delta"] = args[1]
            case "focus-workspace", "move-window-to-workspace":
                cmdArgs["workspace"] = args[1]
            case "set-column-width":
                cmdArgs["width"] = args[1]
            default:
                // Generic argument passing
                for (i, arg) in args.dropFirst().enumerated() {
                    cmdArgs["arg\(i)"] = arg
                }
            }

            request["args"] = cmdArgs
        }
        
        // Send to socket
        guard let response = sendCommand(request) else {
            fputs("Error: Failed to communicate with niri-macos\n", stderr)
            fputs("Is niri-macos running? Start it with: niri-macos\n", stderr)
            exit(1)
        }
        
        // Parse response
        if let data = response.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let success = json["success"] as? Bool, success {
                // Success - print any data if present
                if let resultData = json["data"] as? [String: Any], !resultData.isEmpty {
                    // Sort keys for consistent output
                    let sortedKeys = resultData.keys.sorted()
                    for key in sortedKeys {
                        if let value = resultData[key] {
                            print("\(key): \(value)")
                        }
                    }
                }
                exit(0)
            } else {
                // Error
                let error = json["error"] as? String ?? "Unknown error"
                fputs("Error: \(error)\n", stderr)
                exit(1)
            }
        } else {
            fputs("Error: Invalid response from server\n", stderr)
            fputs("Response: \(response)\n", stderr)
            exit(1)
        }
    }
    
    static func sendCommand(_ request: [String: Any]) -> String? {
        // Create socket
        let sock = socket(AF_UNIX, SOCK_STREAM, 0)
        guard sock >= 0 else {
            return nil
        }
        defer { close(sock) }
        
        // Connect to server
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            socketPath.withCString { cstr in
                _ = strcpy(UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self), cstr)
            }
        }
        
        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                connect(sock, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        
        guard connectResult == 0 else {
            return nil
        }
        
        // Send request
        guard let jsonData = try? JSONSerialization.data(withJSONObject: request),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return nil
        }
        
        _ = jsonString.withCString { cstr in
            write(sock, cstr, strlen(cstr))
        }
        
        // Read response
        var buffer = [CChar](repeating: 0, count: 65536)
        let bytesRead = read(sock, &buffer, buffer.count - 1)
        
        guard bytesRead > 0 else {
            return nil
        }
        
        buffer[bytesRead] = 0
        return String(cString: buffer)
    }
}

NiriMsg.main()
