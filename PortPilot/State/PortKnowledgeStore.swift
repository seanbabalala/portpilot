import Foundation

@MainActor
final class PortKnowledgeStore: ObservableObject {
    enum MatchScope: String, CaseIterable, Identifiable, Sendable {
        case processPort = "process_port"
        case portOnly = "port_only"
        case processOnly = "process_only"

        var id: String { rawValue }

        func label(language: AppLanguage) -> String {
            switch (self, language) {
            case (.processPort, .chinese):
                return "进程+端口"
            case (.processPort, .english):
                return "Process + Port"
            case (.portOnly, .chinese):
                return "仅端口"
            case (.portOnly, .english):
                return "Port Only"
            case (.processOnly, .chinese):
                return "仅进程"
            case (.processOnly, .english):
                return "Process Only"
            }
        }
    }

    enum EntrySource: String, Codable, Sendable {
        case manual
        case ai
    }

    struct Entry: Codable, Hashable, Identifiable, Sendable {
        let key: String
        var label: String?
        var purpose: String?
        var source: EntrySource
        var updatedAt: Date

        var id: String { key }
    }

    struct ResolvedEntry: Identifiable, Hashable, Sendable {
        let entry: Entry
        let scope: MatchScope

        var id: String { entry.key }
    }

    @Published private(set) var entriesByKey: [String: Entry] = [:]

    private let defaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var isHydrating = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        hydrate()
    }

    var allEntries: [Entry] {
        entriesByKey.values.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.key < rhs.key
        }
    }

    func resolvedEntry(for item: PortsStore.ListenerItem) -> ResolvedEntry? {
        for scope in [MatchScope.processPort, .portOnly, .processOnly] {
            let key = makeKey(scope: scope, item: item)
            if let entry = entriesByKey[key] {
                return ResolvedEntry(entry: entry, scope: scope)
            }
        }
        return nil
    }

    func entry(for item: PortsStore.ListenerItem, scope: MatchScope) -> Entry? {
        entriesByKey[makeKey(scope: scope, item: item)]
    }

    func save(
        label: String?,
        purpose: String?,
        scope: MatchScope,
        source: EntrySource = .manual,
        for item: PortsStore.ListenerItem
    ) {
        let key = makeKey(scope: scope, item: item)
        let normalizedLabel = normalizeText(label)
        let normalizedPurpose = normalizeText(purpose)

        if normalizedLabel == nil && normalizedPurpose == nil {
            entriesByKey.removeValue(forKey: key)
            persist()
            return
        }

        let entry = Entry(
            key: key,
            label: normalizedLabel,
            purpose: normalizedPurpose,
            source: source,
            updatedAt: Date()
        )
        entriesByKey[key] = entry
        persist()
    }

    func remove(scope: MatchScope, for item: PortsStore.ListenerItem) {
        let key = makeKey(scope: scope, item: item)
        entriesByKey.removeValue(forKey: key)
        persist()
    }

    private func normalizeText(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func makeKey(scope: MatchScope, item: PortsStore.ListenerItem) -> String {
        let protocolName = item.protocolName.uppercased()
        let processName = item.processName.lowercased()

        switch scope {
        case .processPort:
            return "pp|\(protocolName)|\(item.port)|\(processName)"
        case .portOnly:
            return "po|\(protocolName)|\(item.port)|*"
        case .processOnly:
            return "pn|*|*|\(processName)"
        }
    }

    private func hydrate() {
        guard let rawData = defaults.data(forKey: Keys.portKnowledgeEntries) else {
            entriesByKey = [:]
            return
        }

        do {
            isHydrating = true
            defer { isHydrating = false }
            entriesByKey = try decoder.decode([String: Entry].self, from: rawData)
        } catch {
            entriesByKey = [:]
        }
    }

    private func persist() {
        guard !isHydrating else { return }
        do {
            let data = try encoder.encode(entriesByKey)
            defaults.set(data, forKey: Keys.portKnowledgeEntries)
        } catch {
            defaults.removeObject(forKey: Keys.portKnowledgeEntries)
        }
    }
}

private enum Keys {
    static let portKnowledgeEntries = "settings.portKnowledgeEntries"
}
