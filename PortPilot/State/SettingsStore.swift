import Combine
import Foundation

enum RefreshIntervalOption: Int, CaseIterable, Identifiable, Sendable {
    case oneSecond = 1
    case twoSeconds = 2
    case fiveSeconds = 5
    case tenSeconds = 10

    var id: Int { rawValue }

    var seconds: Int { rawValue }

    var label: String {
        "\(rawValue) seconds"
    }
}

enum PortCountMode: String, CaseIterable, Identifiable, Sendable {
    case portAndPID = "port_and_pid"
    case portOnly = "port_only"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .portAndPID:
            return "A (port + pid)"
        case .portOnly:
            return "B (port only)"
        }
    }
}

@MainActor
final class SettingsStore: ObservableObject {
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

    @Published var enableKill: Bool {
        didSet {
            defaults.set(enableKill, forKey: Keys.enableKill)
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let storedRefresh = defaults.integer(forKey: Keys.refreshInterval)
        self.refreshInterval = RefreshIntervalOption(rawValue: storedRefresh) ?? .twoSeconds

        let storedCountMode = defaults.string(forKey: Keys.countMode) ?? PortCountMode.portAndPID.rawValue
        self.countMode = PortCountMode(rawValue: storedCountMode) ?? .portAndPID

        if defaults.object(forKey: Keys.showCommandLine) == nil {
            self.showCommandLine = false
        } else {
            self.showCommandLine = defaults.bool(forKey: Keys.showCommandLine)
        }

        if defaults.object(forKey: Keys.enableKill) == nil {
            self.enableKill = false
        } else {
            self.enableKill = defaults.bool(forKey: Keys.enableKill)
        }
    }
}

private enum Keys {
    static let refreshInterval = "settings.refreshInterval"
    static let countMode = "settings.countMode"
    static let showCommandLine = "settings.showCommandLine"
    static let enableKill = "settings.enableKill"
}
