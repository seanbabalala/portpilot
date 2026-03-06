import Combine
import Foundation

@MainActor
final class PortsStore: ObservableObject {
    struct ListenerItem: Identifiable, Hashable {
        let id: String
        let listener: PortListener
        let displayName: String
        let firstSeenAt: Date
        let lastSeenAt: Date
        let isNew: Bool

        var processName: String { listener.processName }
        var pid: Int { listener.pid }
        var port: Int { listener.port }
        var user: String? { listener.user }
        var protocolName: String { listener.protocolName }
        var commandLine: String? { listener.commandLine }
        var ppid: Int? { listener.ppid }
        var parentProcessName: String? { listener.parentProcessName }
        var launchSource: String? { listener.launchSource }
        var cpuUsagePercent: Double? { listener.cpuUsagePercent }
        var memoryFootprintMB: Int? { listener.memoryFootprintMB }
    }

    @Published private(set) var listeners: [ListenerItem] = []

    private let newBadgeDuration: TimeInterval
    private var countMode: PortCountMode
    private var stateByKey: [ListenerInstanceKey: ListenerState] = [:]
    private var expirationTasks: [ListenerInstanceKey: Task<Void, Never>] = [:]
    private var cancellables: Set<AnyCancellable> = []
    private var ignoredPorts: Set<Int> = []
    private var ignoredProcesses: Set<String> = []
    private var processAliases: [String: String] = [:]

    init(
        newBadgeDuration: TimeInterval = 5,
        countMode: PortCountMode = .portAndPID,
        settingsStore: SettingsStore? = nil
    ) {
        self.newBadgeDuration = newBadgeDuration
        self.countMode = countMode

        if let settingsStore {
            self.countMode = settingsStore.countMode
            updateRules(
                ignoredPorts: settingsStore.ignoredPorts,
                ignoredProcesses: settingsStore.ignoredProcessNames,
                processAliases: settingsStore.processAliases
            )

            settingsStore.$countMode
                .removeDuplicates()
                .sink { [weak self] nextMode in
                    self?.updateCountMode(nextMode)
                }
                .store(in: &cancellables)

            Publishers.CombineLatest3(
                settingsStore.$ignoredPortsText.removeDuplicates(),
                settingsStore.$ignoredProcessesText.removeDuplicates(),
                settingsStore.$processAliasesText.removeDuplicates()
            )
            .sink { [weak self, weak settingsStore] _, _, _ in
                guard let self, let settingsStore else { return }
                self.updateRules(
                    ignoredPorts: settingsStore.ignoredPorts,
                    ignoredProcesses: settingsStore.ignoredProcessNames,
                    processAliases: settingsStore.processAliases
                )
            }
            .store(in: &cancellables)
        }
    }

    func updateCountMode(_ nextMode: PortCountMode) {
        guard countMode != nextMode else { return }
        countMode = nextMode
        publishSortedListeners()
    }

    func applyScan(_ scannedListeners: [PortListener], at now: Date = Date()) {
        let deduped = dedupe(scannedListeners)
        var nextStateByKey: [ListenerInstanceKey: ListenerState] = [:]

        for (key, listener) in deduped {
            if var existing = stateByKey[key] {
                existing.listener = listener
                existing.lastSeenAt = now

                if existing.isNew,
                   now.timeIntervalSince(existing.firstSeenAt) >= newBadgeDuration {
                    existing.isNew = false
                }

                nextStateByKey[key] = existing
            } else {
                let newState = ListenerState(
                    listener: listener,
                    firstSeenAt: now,
                    lastSeenAt: now,
                    isNew: true,
                    lifecycleToken: UUID()
                )
                nextStateByKey[key] = newState
                scheduleNewBadgeExpiration(for: key, token: newState.lifecycleToken)
            }
        }

        cancelTasksForRemovedKeys(nextKeys: Set(nextStateByKey.keys))

        stateByKey = nextStateByKey
        publishSortedListeners()
    }

    func removeListeners(pid: Int) {
        guard pid > 0 else { return }

        let removedKeys = stateByKey.keys.filter { key in
            key.pid == pid
        }

        guard !removedKeys.isEmpty else { return }

        for key in removedKeys {
            expirationTasks[key]?.cancel()
            expirationTasks.removeValue(forKey: key)
            stateByKey.removeValue(forKey: key)
        }

        publishSortedListeners()
    }

    private func dedupe(_ scannedListeners: [PortListener]) -> [ListenerInstanceKey: PortListener] {
        var deduped: [ListenerInstanceKey: PortListener] = [:]

        for listener in scannedListeners {
            let key = ListenerInstanceKey(listener: listener)
            if deduped[key] == nil {
                deduped[key] = listener
            }
        }

        return deduped
    }

    private func cancelTasksForRemovedKeys(nextKeys: Set<ListenerInstanceKey>) {
        let removedKeys = Set(stateByKey.keys).subtracting(nextKeys)

        for key in removedKeys {
            expirationTasks[key]?.cancel()
            expirationTasks.removeValue(forKey: key)
        }
    }

    private func scheduleNewBadgeExpiration(for key: ListenerInstanceKey, token: UUID) {
        expirationTasks[key]?.cancel()
        let duration = newBadgeDuration

        expirationTasks[key] = Task { [weak self] in
            let nanos = UInt64(duration * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.expireNewBadge(for: key, token: token)
            }
        }
    }

    private func expireNewBadge(for key: ListenerInstanceKey, token: UUID) {
        guard var state = stateByKey[key] else {
            expirationTasks.removeValue(forKey: key)
            return
        }

        guard state.lifecycleToken == token else { return }
        guard state.isNew else {
            expirationTasks.removeValue(forKey: key)
            return
        }

        state.isNew = false
        stateByKey[key] = state
        expirationTasks.removeValue(forKey: key)
        publishSortedListeners()
    }

    private func publishSortedListeners() {
        let projectedStates = projectedStatesForCurrentMode()

        listeners = projectedStates
            .sorted(by: isLeftStateBeforeRightState)
            .map { state in
                ListenerItem(
                    id: itemID(for: state.listener),
                    listener: state.listener,
                    displayName: displayName(for: state.listener),
                    firstSeenAt: state.firstSeenAt,
                    lastSeenAt: state.lastSeenAt,
                    isNew: state.isNew
                )
            }
    }

    private func projectedStatesForCurrentMode() -> [ListenerState] {
        let allStates = applyRules(to: Array(stateByKey.values))

        switch countMode {
        case .portAndPID:
            return allStates
        case .portOnly:
            let grouped = Dictionary(grouping: allStates) { state in
                ListenerPortKey(listener: state.listener)
            }

            return grouped.values.compactMap { group in
                let sortedGroup = group.sorted(by: isLeftStateBeforeRightState)
                guard let primary = sortedGroup.first else { return nil }

                let firstSeenAt = group.map(\.firstSeenAt).min() ?? primary.firstSeenAt
                let lastSeenAt = group.map(\.lastSeenAt).max() ?? primary.lastSeenAt
                let isNew = group.contains(where: \.isNew)

                return ListenerState(
                    listener: primary.listener,
                    firstSeenAt: firstSeenAt,
                    lastSeenAt: lastSeenAt,
                    isNew: isNew,
                    lifecycleToken: primary.lifecycleToken
                )
            }
        }
    }

    private func updateRules(
        ignoredPorts: Set<Int>,
        ignoredProcesses: Set<String>,
        processAliases: [String: String]
    ) {
        self.ignoredPorts = ignoredPorts
        self.ignoredProcesses = ignoredProcesses
        self.processAliases = processAliases
        publishSortedListeners()
    }

    private func applyRules(to states: [ListenerState]) -> [ListenerState] {
        states.compactMap { state in
            guard !isIgnored(state.listener) else { return nil }
            return state
        }
    }

    private func isIgnored(_ listener: PortListener) -> Bool {
        if ignoredPorts.contains(listener.port) {
            return true
        }

        let processKey = listener.processName.lowercased()
        return ignoredProcesses.contains(processKey)
    }

    private func aliasForProcess(_ processName: String) -> String? {
        processAliases[processName.lowercased()]
    }

    private func displayName(for listener: PortListener) -> String {
        aliasForProcess(listener.processName) ?? listener.processName
    }

    private func itemID(for listener: PortListener) -> String {
        switch countMode {
        case .portAndPID:
            return "\(listener.protocolName.lowercased())-\(listener.port)-\(listener.pid)"
        case .portOnly:
            return "\(listener.protocolName.lowercased())-\(listener.port)"
        }
    }

    private func isLeftStateBeforeRightState(_ lhs: ListenerState, _ rhs: ListenerState) -> Bool {
        if lhs.listener.port != rhs.listener.port {
            return lhs.listener.port < rhs.listener.port
        }

        if lhs.listener.pid != rhs.listener.pid {
            return lhs.listener.pid < rhs.listener.pid
        }

        if lhs.listener.protocolName != rhs.listener.protocolName {
            return lhs.listener.protocolName < rhs.listener.protocolName
        }

        if lhs.listener.processName != rhs.listener.processName {
            return lhs.listener.processName < rhs.listener.processName
        }

        return lhs.firstSeenAt < rhs.firstSeenAt
    }
}

private struct ListenerInstanceKey: Hashable {
    let protocolName: String
    let port: Int
    let pid: Int

    init(listener: PortListener) {
        self.protocolName = listener.protocolName.uppercased()
        self.port = listener.port
        self.pid = listener.pid
    }
}

private struct ListenerPortKey: Hashable {
    let protocolName: String
    let port: Int

    init(listener: PortListener) {
        self.protocolName = listener.protocolName.uppercased()
        self.port = listener.port
    }
}

private struct ListenerState {
    var listener: PortListener
    var firstSeenAt: Date
    var lastSeenAt: Date
    var isNew: Bool
    var lifecycleToken: UUID
}
