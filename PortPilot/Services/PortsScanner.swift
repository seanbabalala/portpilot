import Combine
import Foundation

@MainActor
final class PortsScanner: ObservableObject {
    @Published private(set) var consecutiveFailureCount: Int = 0
    @Published private(set) var isUnknown: Bool = false
    @Published private(set) var isScanning: Bool = false
    @Published private(set) var lastSuccessfulScanAt: Date?

    private(set) var refreshInterval: TimeInterval

    private let store: PortsStore
    private var shouldResolveCommandLine: Bool = false
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
        shouldResolveCommandLine = settingsStore?.showCommandLine ?? false
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
                DispatchQueue.main.async { [weak self] in
                    self?.setRefreshInterval(TimeInterval(nextOption.seconds))
                }
            }
            .store(in: &cancellables)

        settingsStore.$showCommandLine
            .removeDuplicates()
            .sink { [weak self] nextValue in
                DispatchQueue.main.async { [weak self] in
                    self?.shouldResolveCommandLine = nextValue
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
                includeCommandLine: shouldResolveCommandLine
            )
            consecutiveFailureCount = 0
            isUnknown = false
            lastSuccessfulScanAt = Date()
            store.applyScan(listeners)
        } catch {
            consecutiveFailureCount += 1
            if consecutiveFailureCount >= 3 {
                isUnknown = true
            }
        }
    }

    private nonisolated func performBackgroundScan(includeCommandLine: Bool) async throws -> [PortListener] {
        try await Task.detached(priority: .utility) {
            let runner = LsofRunner()
            let parser = LsofParser()
            let resolver = ProcessCommandLineResolver()

            let result = try await runner.run()

            let stderrText = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if result.exitCode == 0 || (result.exitCode == 1 && stderrText.isEmpty) {
                let listeners = parser.parse(stdout: result.stdout)
                guard includeCommandLine else { return listeners }
                guard !listeners.isEmpty else { return listeners }

                let commandLineByPID = (try? resolver.resolveCommandLines(
                    for: listeners.map(\.pid)
                )) ?? [:]

                return listeners.map { listener in
                    listener.withCommandLine(commandLineByPID[listener.pid])
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

private struct ProcessCommandLineResolver {
    private let candidateExecutablePaths = [
        "/bin/ps",
        "/usr/bin/ps"
    ]

    func resolveCommandLines(for pids: [Int]) throws -> [Int: String] {
        let uniquePIDs = Array(Set(pids.filter { $0 > 0 })).sorted()
        guard !uniquePIDs.isEmpty else { return [:] }

        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = resolveExecutableURL()
        process.arguments = [
            "-p", uniquePIDs.map(String.init).joined(separator: ","),
            "-o", "pid=",
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

        return parse(output)
    }

    private func parse(_ output: String) -> [Int: String] {
        var result: [Int: String] = [:]

        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            let parts = line.split(maxSplits: 1, whereSeparator: \.isWhitespace)
            guard parts.count == 2 else { continue }

            let pidText = String(parts[0])
            let commandLine = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)

            guard let pid = Int(pidText), !commandLine.isEmpty else { continue }
            result[pid] = commandLine
        }

        return result
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
