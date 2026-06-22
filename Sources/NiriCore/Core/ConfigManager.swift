import Foundation

/// Loads and validates JSON configuration
public class ConfigManager {
    public static let shared = ConfigManager()

    private let logger = Logger.shared
    public private(set) var config = NiriConfig()
    public private(set) var configPath: String

    public static let defaultConfigPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.config/niri-macos/config.json"
    }()

    private init() {
        configPath = Self.defaultConfigPath
    }

    /// Load config from disk. Returns true if a config was loaded, false if using defaults.
    @discardableResult
    public func load(from path: String? = nil) -> Bool {
        if let path = path {
            configPath = path
        }

        guard FileManager.default.fileExists(atPath: configPath) else {
            logger.info("No config file at \(configPath), using defaults")
            config = NiriConfig()
            return false
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: configPath))
            let decoder = JSONDecoder()
            config = try decoder.decode(NiriConfig.self, from: data)
            validate()
            logger.info("Loaded config from \(configPath)")
            return true
        } catch {
            logger.error("Failed to load config from \(configPath): \(error)")
            config = NiriConfig()
            return false
        }
    }

    /// Apply loaded config to all subsystems
    public func apply() {
        LayoutEngine.shared.config = config.layout
        AnimationController.shared.config = config.animation
    }

    /// Clamp values to sane ranges
    private func validate() {
        config.layout.gaps = max(0, min(config.layout.gaps, 100))
        config.layout.outerGaps.top = max(0, min(config.layout.outerGaps.top, 200))
        config.layout.outerGaps.bottom = max(0, min(config.layout.outerGaps.bottom, 200))
        config.layout.outerGaps.left = max(0, min(config.layout.outerGaps.left, 200))
        config.layout.outerGaps.right = max(0, min(config.layout.outerGaps.right, 200))

        if config.layout.presetWidths.isEmpty {
            config.layout.presetWidths = ColumnWidth.presets
        }

        config.input.scrollThreshold = max(1, min(config.input.scrollThreshold, 200))
        config.input.scrollMultiplier = max(0.1, min(config.input.scrollMultiplier, 10))
        config.input.triggerCooldown = max(0, min(config.input.triggerCooldown, 2))
    }

    /// Write default config to disk (for --generate-config)
    public func writeDefault(to path: String? = nil) throws {
        let targetPath = path ?? configPath
        let dir = (targetPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(NiriConfig())
        try data.write(to: URL(fileURLWithPath: targetPath))
        logger.info("Wrote default config to \(targetPath)")
    }
}
