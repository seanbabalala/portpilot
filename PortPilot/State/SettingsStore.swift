import Combine
import Foundation
import ServiceManagement

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case chinese = "zh-Hans"
    case english = "en"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .chinese:
            return "中文"
        case .english:
            return "English"
        }
    }
}

enum RefreshIntervalOption: Int, CaseIterable, Identifiable, Sendable {
    case oneSecond = 1
    case twoSeconds = 2
    case fiveSeconds = 5
    case tenSeconds = 10

    var id: Int { rawValue }

    var seconds: Int { rawValue }

    func label(language: AppLanguage) -> String {
        switch language {
        case .chinese:
            return "\(rawValue) 秒"
        case .english:
            return "\(rawValue)s"
        }
    }
}

enum PortCountMode: String, CaseIterable, Identifiable, Sendable {
    case portAndPID = "port_and_pid"
    case portOnly = "port_only"

    var id: String { rawValue }

    func label(language: AppLanguage) -> String {
        switch self {
        case .portAndPID:
            switch language {
            case .chinese:
                return "按实例（端口 + PID）"
            case .english:
                return "By Instance (Port + PID)"
            }
        case .portOnly:
            switch language {
            case .chinese:
                return "按端口（聚合同端口进程）"
            case .english:
                return "By Port (Merge Same Port)"
            }
        }
    }
}

enum HealthCheckAttemptsOption: Int, CaseIterable, Identifiable, Sendable {
    case three = 3
    case six = 6
    case ten = 10
    case fifteen = 15

    var id: Int { rawValue }

    var attempts: Int { rawValue }

    func label(language: AppLanguage) -> String {
        switch language {
        case .chinese:
            return "\(rawValue) 次"
        case .english:
            return "\(rawValue) tries"
        }
    }
}

enum HealthCheckIntervalOption: Int, CaseIterable, Identifiable, Sendable {
    case ms300 = 300
    case ms500 = 500
    case ms800 = 800
    case ms1200 = 1200

    var id: Int { rawValue }

    var milliseconds: Int { rawValue }

    var nanoseconds: UInt64 {
        UInt64(rawValue) * 1_000_000
    }

    func label(language: AppLanguage) -> String {
        switch self {
        case .ms300:
            switch language {
            case .chinese:
                return "0.3 秒"
            case .english:
                return "0.3s"
            }
        case .ms500:
            switch language {
            case .chinese:
                return "0.5 秒"
            case .english:
                return "0.5s"
            }
        case .ms800:
            switch language {
            case .chinese:
                return "0.8 秒"
            case .english:
                return "0.8s"
            }
        case .ms1200:
            switch language {
            case .chinese:
                return "1.2 秒"
            case .english:
                return "1.2s"
            }
        }
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    @Published var appLanguage: AppLanguage {
        didSet {
            defaults.set(appLanguage.rawValue, forKey: Keys.appLanguage)
        }
    }

    @Published var refreshInterval: RefreshIntervalOption {
        didSet {
            defaults.set(refreshInterval.rawValue, forKey: Keys.refreshInterval)
        }
    }

    @Published var countMode: PortCountMode {
        didSet {
            defaults.set(countMode.rawValue, forKey: Keys.countMode)
        }
    }

    @Published var showCommandLine: Bool {
        didSet {
            defaults.set(showCommandLine, forKey: Keys.showCommandLine)
        }
    }

    @Published var showResourceBadges: Bool {
        didSet {
            defaults.set(showResourceBadges, forKey: Keys.showResourceBadges)
        }
    }

    @Published var enableKill: Bool {
        didSet {
            defaults.set(enableKill, forKey: Keys.enableKill)
        }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
            guard !isHydratingLaunchAtLogin else { return }
            applyLaunchAtLoginPreference()
        }
    }

    @Published private(set) var launchAtLoginError: String?

    @Published var ignoredPortsText: String {
        didSet {
            defaults.set(ignoredPortsText, forKey: Keys.ignoredPortsText)
        }
    }

    @Published var ignoredProcessesText: String {
        didSet {
            defaults.set(ignoredProcessesText, forKey: Keys.ignoredProcessesText)
        }
    }

    @Published var processAliasesText: String {
        didSet {
            defaults.set(processAliasesText, forKey: Keys.processAliasesText)
        }
    }

    @Published var notifyOnNewPort: Bool {
        didSet {
            defaults.set(notifyOnNewPort, forKey: Keys.notifyOnNewPort)
        }
    }

    @Published var notifyOnPortConflict: Bool {
        didSet {
            defaults.set(notifyOnPortConflict, forKey: Keys.notifyOnPortConflict)
        }
    }

    @Published var notifyOnScannerFailure: Bool {
        didSet {
            defaults.set(notifyOnScannerFailure, forKey: Keys.notifyOnScannerFailure)
        }
    }

    @Published var autoSuggestProfiles: Bool {
        didSet {
            defaults.set(autoSuggestProfiles, forKey: Keys.autoSuggestProfiles)
        }
    }

    @Published var healthCheckMaxAttempts: HealthCheckAttemptsOption {
        didSet {
            defaults.set(healthCheckMaxAttempts.rawValue, forKey: Keys.healthCheckMaxAttempts)
        }
    }

    @Published var healthCheckProbeInterval: HealthCheckIntervalOption {
        didSet {
            defaults.set(healthCheckProbeInterval.rawValue, forKey: Keys.healthCheckProbeInterval)
        }
    }

    private let defaults: UserDefaults
    private var isHydratingLaunchAtLogin = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let storedLanguage = defaults.string(forKey: Keys.appLanguage),
           let parsed = AppLanguage(rawValue: storedLanguage) {
            self.appLanguage = parsed
        } else if Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true {
            self.appLanguage = .chinese
        } else {
            self.appLanguage = .english
        }

        let storedRefresh = defaults.integer(forKey: Keys.refreshInterval)
        self.refreshInterval = RefreshIntervalOption(rawValue: storedRefresh) ?? .twoSeconds

        let storedCountMode = defaults.string(forKey: Keys.countMode) ?? PortCountMode.portAndPID.rawValue
        self.countMode = PortCountMode(rawValue: storedCountMode) ?? .portAndPID

        if defaults.object(forKey: Keys.showCommandLine) == nil {
            self.showCommandLine = false
        } else {
            self.showCommandLine = defaults.bool(forKey: Keys.showCommandLine)
        }

        if defaults.object(forKey: Keys.showResourceBadges) == nil {
            self.showResourceBadges = true
        } else {
            self.showResourceBadges = defaults.bool(forKey: Keys.showResourceBadges)
        }

        if defaults.object(forKey: Keys.enableKill) == nil {
            self.enableKill = false
        } else {
            self.enableKill = defaults.bool(forKey: Keys.enableKill)
        }

        if defaults.object(forKey: Keys.launchAtLogin) == nil {
            self.launchAtLogin = false
        } else {
            self.launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
        }
        self.launchAtLoginError = nil

        self.ignoredPortsText = defaults.string(forKey: Keys.ignoredPortsText) ?? ""
        self.ignoredProcessesText = defaults.string(forKey: Keys.ignoredProcessesText) ?? ""
        self.processAliasesText = defaults.string(forKey: Keys.processAliasesText) ?? ""

        if defaults.object(forKey: Keys.notifyOnNewPort) == nil {
            self.notifyOnNewPort = true
        } else {
            self.notifyOnNewPort = defaults.bool(forKey: Keys.notifyOnNewPort)
        }

        if defaults.object(forKey: Keys.notifyOnPortConflict) == nil {
            self.notifyOnPortConflict = true
        } else {
            self.notifyOnPortConflict = defaults.bool(forKey: Keys.notifyOnPortConflict)
        }

        if defaults.object(forKey: Keys.notifyOnScannerFailure) == nil {
            self.notifyOnScannerFailure = true
        } else {
            self.notifyOnScannerFailure = defaults.bool(forKey: Keys.notifyOnScannerFailure)
        }

        if defaults.object(forKey: Keys.autoSuggestProfiles) == nil {
            self.autoSuggestProfiles = true
        } else {
            self.autoSuggestProfiles = defaults.bool(forKey: Keys.autoSuggestProfiles)
        }

        let storedHealthAttempts = defaults.integer(forKey: Keys.healthCheckMaxAttempts)
        self.healthCheckMaxAttempts = HealthCheckAttemptsOption(rawValue: storedHealthAttempts) ?? .six

        let storedHealthInterval = defaults.integer(forKey: Keys.healthCheckProbeInterval)
        self.healthCheckProbeInterval = HealthCheckIntervalOption(rawValue: storedHealthInterval) ?? .ms500

        syncLaunchAtLoginFromSystem()
    }

    var ignoredPorts: Set<Int> {
        tokenize(ignoredPortsText)
            .compactMap(Int.init)
            .reduce(into: Set<Int>()) { partialResult, value in
                guard value > 0 else { return }
                partialResult.insert(value)
            }
    }

    var ignoredProcessNames: Set<String> {
        Set(
            tokenize(ignoredProcessesText)
                .map { $0.lowercased() }
                .filter { !$0.isEmpty }
        )
    }

    var processAliases: [String: String] {
        var aliases: [String: String] = [:]
        let separators = CharacterSet.newlines.union(.init(charactersIn: ",;"))
        let entries = processAliasesText
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for entry in entries {
            let parts: [String]
            if entry.contains("=") {
                parts = entry.split(separator: "=", maxSplits: 1).map(String.init)
            } else if entry.contains(":") {
                parts = entry.split(separator: ":", maxSplits: 1).map(String.init)
            } else {
                continue
            }

            guard parts.count == 2 else { continue }
            let raw = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let alias = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty, !alias.isEmpty else { continue }
            aliases[raw] = alias
        }

        return aliases
    }

    private func tokenize(_ text: String) -> [String] {
        text.components(
            separatedBy: CharacterSet.whitespacesAndNewlines.union(.init(charactersIn: ",;"))
        )
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    }

    private func syncLaunchAtLoginFromSystem() {
        guard #available(macOS 13.0, *) else { return }
        let status = SMAppService.mainApp.status

        isHydratingLaunchAtLogin = true
        defer { isHydratingLaunchAtLogin = false }

        switch status {
        case .enabled:
            launchAtLogin = true
        case .notRegistered, .notFound:
            launchAtLogin = false
        case .requiresApproval:
            launchAtLogin = true
        @unknown default:
            break
        }
    }

    private func applyLaunchAtLoginPreference() {
        guard #available(macOS 13.0, *) else {
            launchAtLoginError = tr("当前系统不支持开机启动 API。", "Launch at login API is unavailable on this macOS version.")
            return
        }

        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = tr(
                "设置开机启动失败：\(error.localizedDescription)",
                "Failed to update launch-at-login setting: \(error.localizedDescription)"
            )
            syncLaunchAtLoginFromSystem()
        }
    }
}

extension SettingsStore {
    var isEnglish: Bool {
        appLanguage == .english
    }

    func tr(_ chinese: String, _ english: String) -> String {
        isEnglish ? english : chinese
    }
}

private enum Keys {
    static let appLanguage = "settings.appLanguage"
    static let refreshInterval = "settings.refreshInterval"
    static let countMode = "settings.countMode"
    static let showCommandLine = "settings.showCommandLine"
    static let showResourceBadges = "settings.showResourceBadges"
    static let enableKill = "settings.enableKill"
    static let launchAtLogin = "settings.launchAtLogin"
    static let ignoredPortsText = "settings.ignoredPortsText"
    static let ignoredProcessesText = "settings.ignoredProcessesText"
    static let processAliasesText = "settings.processAliasesText"
    static let notifyOnNewPort = "settings.notifyOnNewPort"
    static let notifyOnPortConflict = "settings.notifyOnPortConflict"
    static let notifyOnScannerFailure = "settings.notifyOnScannerFailure"
    static let autoSuggestProfiles = "settings.autoSuggestProfiles"
    static let healthCheckMaxAttempts = "settings.healthCheckMaxAttempts"
    static let healthCheckProbeInterval = "settings.healthCheckProbeInterval"
}
