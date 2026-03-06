import Combine
import Foundation
import UniformTypeIdentifiers
import UserNotifications

@MainActor
final class PortsScanner: ObservableObject {
    @Published private(set) var consecutiveFailureCount: Int = 0
    @Published private(set) var isUnknown: Bool = false
    @Published private(set) var isScanning: Bool = false
    @Published private(set) var lastSuccessfulScanAt: Date?

    private(set) var refreshInterval: TimeInterval

    private let store: PortsStore
    private let notifications = PortNotifications()

    private var shouldResolveCommandLine: Bool = false
    private var autoSuggestProfiles: Bool = true
    private var notifyOnNewPort: Bool = true
    private var notifyOnPortConflict: Bool = true
    private var notifyOnScannerFailure: Bool = true
    private var appLanguage: AppLanguage = .chinese
    private var ignoredPorts: Set<Int> = []
    private var ignoredProcesses: Set<String> = []

    private var knownListeningPorts: Set<Int> = []
    private var activeConflictPorts: Set<Int> = []
    private var hasNotifiedPersistentFailure: Bool = false

    private var scanLoopTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    init(
        store: PortsStore,
        refreshInterval: TimeInterval = 2,
        settingsStore: SettingsStore? = nil
    ) {
        self.store = store
        self.refreshInterval = refreshInterval

        bindSettings(settingsStore)

        guard let settingsStore else { return }
        shouldResolveCommandLine = settingsStore.showCommandLine
        autoSuggestProfiles = settingsStore.autoSuggestProfiles
        ignoredPorts = settingsStore.ignoredPorts
        ignoredProcesses = settingsStore.ignoredProcessNames
        notifyOnNewPort = settingsStore.notifyOnNewPort
        notifyOnPortConflict = settingsStore.notifyOnPortConflict
        notifyOnScannerFailure = settingsStore.notifyOnScannerFailure
        appLanguage = settingsStore.appLanguage

        if notifyOnNewPort || notifyOnPortConflict || notifyOnScannerFailure {
            notifications.requestAuthorizationIfNeeded()
        }
    }

    deinit {
        scanLoopTask?.cancel()
    }

    func setRefreshInterval(_ seconds: TimeInterval) {
        guard seconds > 0 else { return }
        guard refreshInterval != seconds else { return }

        refreshInterval = seconds

        guard scanLoopTask != nil else { return }
        stop()
        start()
    }

    func start() {
        guard scanLoopTask == nil else { return }

        scanLoopTask = Task { [weak self] in
            await self?.runScanLoop()
        }
    }

    func stop() {
        scanLoopTask?.cancel()
        scanLoopTask = nil
    }

    func rescanNow() async {
        await scanOnce()
    }

    private func bindSettings(_ settingsStore: SettingsStore?) {
        guard let settingsStore else { return }

        settingsStore.$refreshInterval
            .removeDuplicates()
            .sink { [weak self] nextOption in
                self?.setRefreshInterval(TimeInterval(nextOption.seconds))
            }
            .store(in: &cancellables)

        settingsStore.$showCommandLine
            .removeDuplicates()
            .sink { [weak self] nextValue in
                self?.shouldResolveCommandLine = nextValue
            }
            .store(in: &cancellables)

        settingsStore.$appLanguage
            .removeDuplicates()
            .sink { [weak self] nextLanguage in
                self?.appLanguage = nextLanguage
            }
            .store(in: &cancellables)

        settingsStore.$autoSuggestProfiles
            .removeDuplicates()
            .sink { [weak self] nextValue in
                self?.autoSuggestProfiles = nextValue
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(
            settingsStore.$ignoredPortsText.removeDuplicates(),
            settingsStore.$ignoredProcessesText.removeDuplicates()
        )
        .sink { [weak self, weak settingsStore] _, _ in
            guard let self, let settingsStore else { return }
            self.ignoredPorts = settingsStore.ignoredPorts
            self.ignoredProcesses = settingsStore.ignoredProcessNames
        }
        .store(in: &cancellables)

        Publishers.CombineLatest3(
            settingsStore.$notifyOnNewPort.removeDuplicates(),
            settingsStore.$notifyOnPortConflict.removeDuplicates(),
            settingsStore.$notifyOnScannerFailure.removeDuplicates()
        )
        .sink { [weak self] newPort, conflict, scannerFailure in
            guard let self else { return }
            self.notifyOnNewPort = newPort
            self.notifyOnPortConflict = conflict
            self.notifyOnScannerFailure = scannerFailure

            if newPort || conflict || scannerFailure {
                self.notifications.requestAuthorizationIfNeeded()
            }
        }
        .store(in: &cancellables)
    }

    private func runScanLoop() async {
        await scanOnce()

        while !Task.isCancelled {
            let nanos = UInt64(refreshInterval * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)

            guard !Task.isCancelled else { return }
            await scanOnce()
        }
    }

    private func scanOnce() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }

        do {
            let listeners = try await performBackgroundScan(
                includeCommandLine: shouldResolveCommandLine || autoSuggestProfiles
            )
            let filteredForNotifications = applyNotificationFilters(listeners)
            let hadSuccessfulScanBefore = lastSuccessfulScanAt != nil

            consecutiveFailureCount = 0
            isUnknown = false
            hasNotifiedPersistentFailure = false
            lastSuccessfulScanAt = Date()

            store.applyScan(listeners)
            if hadSuccessfulScanBefore {
                emitScanNotifications(for: filteredForNotifications)
            } else {
                knownListeningPorts = Set(filteredForNotifications.map(\.port))
                let groupedByPort = Dictionary(grouping: filteredForNotifications, by: \.port)
                activeConflictPorts = Set(groupedByPort.compactMap { port, group in
                    Set(group.map(\.pid)).count > 1 ? port : nil
                })
            }
        } catch {
            consecutiveFailureCount += 1
            if consecutiveFailureCount >= 3 {
                isUnknown = true
                if notifyOnScannerFailure && !hasNotifiedPersistentFailure {
                    hasNotifiedPersistentFailure = true
                    notifications.send(
                        identifier: "scanner-failure",
                        title: localized("PortPilot 扫描异常", "PortPilot Scan Failure"),
                        body: localized(
                            "连续 \(consecutiveFailureCount) 次扫描失败，菜单将显示 : —",
                            "Scan failed \(consecutiveFailureCount) times in a row; menu will display : —"
                        )
                    )
                }
            }
        }
    }

    private func applyNotificationFilters(_ listeners: [PortListener]) -> [PortListener] {
        listeners.filter { listener in
            if ignoredPorts.contains(listener.port) {
                return false
            }

            return !ignoredProcesses.contains(listener.processName.lowercased())
        }
    }

    private func emitScanNotifications(for listeners: [PortListener]) {
        let portSet = Set(listeners.map(\.port))

        if notifyOnNewPort {
            let newPorts = portSet.subtracting(knownListeningPorts)
            if !newPorts.isEmpty {
                let preview = newPorts.sorted().prefix(4).map(String.init).joined(separator: ", ")
                let body = newPorts.count > 4
                    ? localized("新增监听端口：\(preview) 等 \(newPorts.count) 个", "New listening ports: \(preview) and \(newPorts.count - 4) more")
                    : localized("新增监听端口：\(preview)", "New listening ports: \(preview)")
                notifications.send(
                    identifier: "new-ports",
                    title: localized("发现新监听端口", "New Listening Ports Detected"),
                    body: body
                )
            }
        }

        let groupedByPort = Dictionary(grouping: listeners, by: \.port)
        let conflictPorts = Set(groupedByPort.compactMap { port, group in
            let uniquePIDs = Set(group.map(\.pid))
            return uniquePIDs.count > 1 ? port : nil
        })

        if notifyOnPortConflict {
            let newConflictPorts = conflictPorts.subtracting(activeConflictPorts)
            if !newConflictPorts.isEmpty {
                let preview = newConflictPorts.sorted().prefix(4).map(String.init).joined(separator: ", ")
                let body = newConflictPorts.count > 4
                    ? localized("疑似端口冲突：\(preview) 等 \(newConflictPorts.count) 个", "Possible port conflicts: \(preview) and \(newConflictPorts.count - 4) more")
                    : localized("疑似端口冲突：\(preview)", "Possible port conflicts: \(preview)")
                notifications.send(
                    identifier: "port-conflict",
                    title: localized("发现端口冲突", "Port Conflict Detected"),
                    body: body
                )
            }
        }

        knownListeningPorts = portSet
        activeConflictPorts = conflictPorts
    }

    private func localized(_ chinese: String, _ english: String) -> String {
        appLanguage == .english ? english : chinese
    }

    private nonisolated func performBackgroundScan(includeCommandLine: Bool) async throws -> [PortListener] {
        try await Task.detached(priority: .utility) {
            let runner = LsofRunner()
            let parser = LsofParser()
            let metadataResolver = ProcessMetadataResolver()

            let result = try await runner.run()

            let stderrText = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if result.exitCode == 0 || (result.exitCode == 1 && stderrText.isEmpty) {
                let listeners = parser.parse(stdout: result.stdout)
                guard !listeners.isEmpty else { return listeners }

                let metadataByPID = (try? metadataResolver.resolveMetadata(for: listeners.map(\.pid))) ?? [:]

                return listeners.map { listener in
                    let metadata = metadataByPID[listener.pid]
                    let commandLine = includeCommandLine ? metadata?.commandLine : nil

                    return listener
                        .withCommandLine(commandLine)
                        .withMetadata(
                            ppid: metadata?.ppid,
                            parentProcessName: metadata?.parentProcessName,
                            launchSource: metadata?.launchSource
                        )
                        .withResourceUsage(
                            cpuUsagePercent: metadata?.cpuUsagePercent,
                            memoryFootprintMB: metadata?.memoryFootprintMB
                        )
                }
            }

            throw PortsScannerError.commandFailed(
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }.value
    }
}

enum PortsScannerError: Error {
    case commandFailed(exitCode: Int32, stderr: String)
}

private struct ProcessMetadata {
    let commandLine: String?
    let ppid: Int?
    let parentProcessName: String?
    let launchSource: String?
    let cpuUsagePercent: Double?
    let memoryFootprintMB: Int?
}

private struct ProcessRow {
    let pid: Int
    let ppid: Int
    let cpuUsagePercent: Double?
    let rssKB: Int?
    let commandLine: String
}

private struct ProcessMetadataResolver {
    private let candidateExecutablePaths = [
        "/bin/ps",
        "/usr/bin/ps"
    ]

    func resolveMetadata(for pids: [Int]) throws -> [Int: ProcessMetadata] {
        let uniquePIDs = Array(Set(pids.filter { $0 > 0 })).sorted()
        guard !uniquePIDs.isEmpty else { return [:] }

        let rows = try fetchRows(for: uniquePIDs)
        let parentPIDs = Array(Set(rows.map(\.ppid).filter { $0 > 0 })).sorted()
        let parentRows = try fetchRows(for: parentPIDs)
        let parentRowsByPID = Dictionary(uniqueKeysWithValues: parentRows.map { ($0.pid, $0) })

        return rows.reduce(into: [Int: ProcessMetadata]()) { partialResult, row in
            let parentRow = parentRowsByPID[row.ppid]
            let parentName = parentRow.map { processName(from: $0.commandLine) }
            partialResult[row.pid] = ProcessMetadata(
                commandLine: row.commandLine.isEmpty ? nil : row.commandLine,
                ppid: row.ppid > 0 ? row.ppid : nil,
                parentProcessName: parentName,
                launchSource: inferLaunchSource(
                    commandLine: row.commandLine,
                    parentProcessName: parentName
                ),
                cpuUsagePercent: row.cpuUsagePercent,
                memoryFootprintMB: row.rssKB.map { rssKB in
                    Int((Double(rssKB) / 1024.0).rounded())
                }
            )
        }
    }

    private func fetchRows(for pids: [Int]) throws -> [ProcessRow] {
        guard !pids.isEmpty else { return [] }

        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = resolveExecutableURL()
        process.arguments = [
            "-p", pids.map(String.init).joined(separator: ","),
            "-o", "pid=",
            "-o", "ppid=",
            "-o", "%cpu=",
            "-o", "rss=",
            "-o", "command="
        ]
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: stdoutData, as: UTF8.self)

        guard process.terminationStatus == 0 else {
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let errorText = String(decoding: stderrData, as: UTF8.self)
            throw ProcessCommandLineResolverError.commandFailed(
                exitCode: process.terminationStatus,
                stderr: errorText
            )
        }

        return parseRows(output)
    }

    private func parseRows(_ output: String) -> [ProcessRow] {
        output.split(whereSeparator: \.isNewline).compactMap { rawLine in
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { return nil }

            let parts = line.split(maxSplits: 4, whereSeparator: \.isWhitespace)
            guard parts.count >= 4 else { return nil }
            guard let pid = Int(parts[0]), let ppid = Int(parts[1]) else { return nil }

            let cpuUsagePercent = Double(parts[2])
            let rssKB = Int(parts[3])
            let commandLine = parts.count == 5
                ? String(parts[4]).trimmingCharacters(in: .whitespacesAndNewlines)
                : ""

            return ProcessRow(
                pid: pid,
                ppid: ppid,
                cpuUsagePercent: cpuUsagePercent,
                rssKB: rssKB,
                commandLine: commandLine
            )
        }
    }

    private func processName(from commandLine: String) -> String {
        let firstToken = commandLine.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? commandLine
        let sanitized = firstToken
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        if let candidate = sanitized.split(separator: "/").last {
            return String(candidate)
        }
        return sanitized
    }

    private func inferLaunchSource(
        commandLine: String,
        parentProcessName: String?
    ) -> String {
        let lowerCommand = commandLine.lowercased()
        let lowerParent = parentProcessName?.lowercased() ?? ""

        if lowerParent == "launchd" || lowerCommand.contains("launchctl") {
            return "launchd"
        }

        if lowerCommand.contains("/opt/homebrew")
            || lowerCommand.contains("/usr/local")
            || lowerCommand.contains("/cellar/")
            || lowerParent == "brew" {
            return "brew"
        }

        if lowerCommand.contains("docker")
            || lowerParent.contains("docker")
            || lowerParent.contains("containerd") {
            return "docker"
        }

        if lowerCommand.hasPrefix("ssh ")
            || lowerParent == "ssh"
            || lowerCommand.contains("autossh") {
            return "ssh"
        }

        if lowerCommand.contains(".app/contents/macos/") {
            return "App Bundle"
        }

        return parentProcessName ?? "未知来源"
    }

    private func resolveExecutableURL() -> URL {
        let fileManager = FileManager.default

        for path in candidateExecutablePaths where fileManager.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }

        return URL(fileURLWithPath: candidateExecutablePaths[0])
    }
}

private enum ProcessCommandLineResolverError: Error {
    case commandFailed(exitCode: Int32, stderr: String)
}

private final class PortNotifications {
    private let center = UNUserNotificationCenter.current()
    private var requestedAuthorization = false
    private var lastSentAtByIdentifier: [String: Date] = [:]

    func requestAuthorizationIfNeeded() {
        guard !requestedAuthorization else { return }
        requestedAuthorization = true

        center.requestAuthorization(options: [.alert, .sound]) { _, _ in
            return
        }
    }

    func send(
        identifier: String,
        title: String,
        body: String,
        minimumInterval: TimeInterval = 20
    ) {
        let now = Date()
        if let lastSentAt = lastSentAtByIdentifier[identifier],
           now.timeIntervalSince(lastSentAt) < minimumInterval {
            return
        }
        lastSentAtByIdentifier[identifier] = now

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let iconAttachment = makeAppIconAttachment() {
            content.attachments = [iconAttachment]
        }

        let request = UNNotificationRequest(
            identifier: "portpilot.\(identifier)",
            content: content,
            trigger: nil
        )
        center.add(request)
    }

    private func makeAppIconAttachment() -> UNNotificationAttachment? {
        guard let iconURL = bundledAppIconURL() else { return nil }

        let typeHint: String?
        switch iconURL.pathExtension.lowercased() {
        case "png":
            typeHint = UTType.png.identifier
        case "icns":
            typeHint = UTType.icns.identifier
        default:
            typeHint = nil
        }

        let options: [AnyHashable: Any]? = typeHint.map {
            [UNNotificationAttachmentOptionsTypeHintKey: $0]
        }

        return try? UNNotificationAttachment(
            identifier: "portpilot.appicon",
            url: iconURL,
            options: options
        )
    }

    private func bundledAppIconURL() -> URL? {
        if let iconName = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleIconFile"
        ) as? String, !iconName.isEmpty {
            if let exactURL = Bundle.main.url(forResource: iconName, withExtension: nil) {
                return exactURL
            }

            let iconURL = URL(fileURLWithPath: iconName)
            let baseName = iconURL.deletingPathExtension().lastPathComponent
            let ext = iconURL.pathExtension

            if !ext.isEmpty,
               let explicitURL = Bundle.main.url(forResource: baseName, withExtension: ext) {
                return explicitURL
            }

            if let inferredICNSURL = Bundle.main.url(forResource: iconName, withExtension: "icns") {
                return inferredICNSURL
            }
        }

        return Bundle.main.url(forResource: "AppIcon", withExtension: "icns")
    }
}
