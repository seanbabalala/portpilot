import AppKit
import Darwin
import Foundation

struct CommandProfile: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let note: String?
    let cwd: String
    let command: String
    let ports: [Int]
    let tags: [String]
    let env: [String: String]

    init(
        id: String? = nil,
        name: String,
        note: String? = nil,
        cwd: String,
        command: String,
        ports: [Int] = [],
        tags: [String] = [],
        env: [String: String] = [:]
    ) {
        self.id = id ?? Self.makeID(name: name, cwd: cwd, command: command)
        self.name = name
        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedNote, !trimmedNote.isEmpty {
            self.note = trimmedNote
        } else {
            self.note = nil
        }
        self.cwd = cwd
        self.command = command
        self.ports = ports
        self.tags = tags
        self.env = env
    }

    static func makeID(name: String, cwd: String, command: String) -> String {
        "\(name.lowercased())::\(cwd.lowercased())::\(command.lowercased())"
    }
}

struct RunningCommandInfo: Identifiable, Hashable {
    let id: String
    let profileID: String
    let pid: Int32
    let startedAt: Date
    let command: String
    let cwd: String
}

struct CommandEvent: Identifiable, Hashable, Sendable {
    enum Level: String, Sendable {
        case info
        case warning
        case error
    }

    let id: String
    let timestamp: Date
    let level: Level
    let message: String
    let profileName: String?

    init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        level: Level,
        message: String,
        profileName: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.message = message
        self.profileName = profileName
    }
}

@MainActor
final class CommandProfilesStore: ObservableObject {
    enum AddSuggestedProfileResult {
        case added(name: String)
        case updated(name: String)
        case duplicate(name: String)
        case invalid(reason: String)
        case failed(reason: String)
    }

    enum RebindPortResult {
        case updated(
            name: String,
            oldPort: Int,
            newPort: Int,
            restarted: Bool,
            strategy: RebindPortStrategy
        )
        case unchanged(reason: String)
        case invalid(reason: String)
        case failed(reason: String)
    }

    enum RebindPortStrategy {
        case commandArgument
        case frameworkTemplate
        case packageScriptArgument
        case existingPortEnvironment
        case injectedPortEnvironment

        var hint: String {
            switch self {
            case .commandArgument:
                return "参数已更新"
            case .frameworkTemplate:
                return "框架参数模板已应用"
            case .packageScriptArgument:
                return "脚本透传参数已应用"
            case .existingPortEnvironment:
                return "环境变量已更新"
            case .injectedPortEnvironment:
                return "已注入 PORT 环境变量"
            }
        }
    }

    @Published private(set) var profiles: [CommandProfile] = []
    @Published private(set) var runningByProfileID: [String: RunningCommandInfo] = [:]
    @Published private(set) var stoppingProfileIDs: Set<String> = []
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var recentEvents: [CommandEvent] = []

    var profilesFileURL: URL { yamlStore.fileURL }

    private let yamlStore: CommandProfilesYAMLStore
    private let defaults: UserDefaults
    private var managedProcesses: [String: ManagedProcess] = [:]
    private var dismissedSuggestionSignatures: Set<String> = []

    init(
        yamlStore: CommandProfilesYAMLStore = CommandProfilesYAMLStore(),
        defaults: UserDefaults = .standard
    ) {
        self.yamlStore = yamlStore
        self.defaults = defaults
        self.dismissedSuggestionSignatures = Set(
            defaults.stringArray(forKey: Keys.dismissedSuggestionSignatures) ?? []
        )
        reloadProfiles()
    }

    func reloadProfiles() {
        do {
            let loadedProfiles = try yamlStore.loadProfiles()
            let normalizedProfiles = normalizedProfilesKeepingAtMostOneMock(loadedProfiles)
            profiles = normalizedProfiles

            if normalizedProfiles != loadedProfiles {
                do {
                    try yamlStore.saveProfiles(normalizedProfiles)
                } catch {
                    appendEvent(level: .warning, message: "已规范化启动命令配置，但写回 profiles.yaml 失败：\(error.localizedDescription)")
                }
            }

            lastErrorMessage = nil
            appendEvent(level: .info, message: "配置已重载，共 \(profiles.count) 条命令。")
        } catch {
            lastErrorMessage = "读取 profiles.yaml 失败：\(error.localizedDescription)"
            appendEvent(level: .error, message: lastErrorMessage ?? "读取 profiles.yaml 失败。")
        }
    }

    func openProfilesFile() {
        do {
            try yamlStore.ensureFileExists()
            NSWorkspace.shared.open(yamlStore.fileURL)
            appendEvent(level: .info, message: "已打开 profiles.yaml。")
        } catch {
            lastErrorMessage = "打开 profiles.yaml 失败：\(error.localizedDescription)"
            appendEvent(level: .error, message: lastErrorMessage ?? "打开 profiles.yaml 失败。")
        }
    }

    func isRunning(_ profile: CommandProfile) -> Bool {
        runningByProfileID[profile.id] != nil
    }

    func isStopping(_ profile: CommandProfile) -> Bool {
        stoppingProfileIDs.contains(profile.id)
    }

    func start(profile: CommandProfile) {
        guard !isRunning(profile) else { return }

        do {
            let managed = try makeManagedProcess(for: profile)
            let process = managed.process

            process.terminationHandler = { [weak self] _ in
                Task { @MainActor in
                    self?.handleProcessTerminated(for: profile.id)
                }
            }

            try process.run()

            managedProcesses[profile.id] = managed
            runningByProfileID[profile.id] = RunningCommandInfo(
                id: profile.id,
                profileID: profile.id,
                pid: process.processIdentifier,
                startedAt: Date(),
                command: profile.command,
                cwd: profile.cwd
            )
            lastErrorMessage = nil
            appendEvent(
                level: .info,
                message: "已启动（PID \(process.processIdentifier)）",
                profileName: profile.name
            )
        } catch {
            lastErrorMessage = "启动失败（\(profile.name)）：\(error.localizedDescription)"
            appendEvent(level: .error, message: lastErrorMessage ?? "启动失败。", profileName: profile.name)
        }
    }

    func stop(profile: CommandProfile) async {
        guard let managed = managedProcesses[profile.id] else { return }
        guard !stoppingProfileIDs.contains(profile.id) else { return }

        stoppingProfileIDs.insert(profile.id)
        await terminateManagedProcess(managed)
        stoppingProfileIDs.remove(profile.id)
        appendEvent(level: .info, message: "已停止。", profileName: profile.name)
    }

    func restart(profile: CommandProfile) {
        Task {
            await stop(profile: profile)
            start(profile: profile)
            appendEvent(level: .info, message: "已重启。", profileName: profile.name)
        }
    }

    func startAll() {
        for profile in profiles {
            start(profile: profile)
        }
        appendEvent(level: .info, message: "已触发全部启动。")
    }

    func stopAll() {
        for profile in profiles where isRunning(profile) {
            Task {
                await stop(profile: profile)
            }
        }
        appendEvent(level: .info, message: "已触发全部停止。")
    }

    var workspaceNames: [String] {
        let names = profiles.compactMap(workspaceName(for:))
        return Array(Set(names)).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    func profiles(inWorkspace workspace: String?) -> [CommandProfile] {
        let list: [CommandProfile]
        if let workspace, !workspace.isEmpty {
            list = profiles.filter { workspaceName(for: $0) == workspace }
        } else {
            list = profiles
        }

        return list.sorted(by: sortProfiles)
    }

    func startWorkspace(named workspace: String?) {
        let targets = profiles(inWorkspace: workspace)
        for profile in targets {
            start(profile: profile)
        }

        if let workspace, !workspace.isEmpty {
            appendEvent(level: .info, message: "已触发场景启动：\(workspace)。")
        } else {
            appendEvent(level: .info, message: "已触发全部启动。")
        }
    }

    func stopWorkspace(named workspace: String?) {
        let targets = profiles(inWorkspace: workspace).filter { isRunning($0) }
        for profile in targets {
            Task { await stop(profile: profile) }
        }

        if let workspace, !workspace.isEmpty {
            appendEvent(level: .info, message: "已触发场景停止：\(workspace)。")
        } else {
            appendEvent(level: .info, message: "已触发全部停止。")
        }
    }

    func restartWorkspace(named workspace: String?) {
        let targets = profiles(inWorkspace: workspace)
        for profile in targets {
            restart(profile: profile)
        }

        if let workspace, !workspace.isEmpty {
            appendEvent(level: .info, message: "已触发场景重启：\(workspace)。")
        } else {
            appendEvent(level: .info, message: "已触发全部重启。")
        }
    }

    func workspaceName(for profile: CommandProfile) -> String? {
        let match = profile.tags.first { tag in
            let lower = tag.lowercased()
            return lower.hasPrefix("workspace:") || lower.hasPrefix("ws:")
        }
        guard let match else { return nil }
        if let index = match.firstIndex(of: ":") {
            let value = match[match.index(after: index)...].trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }
        return nil
    }

    func addSuggestedProfile(
        preferredName: String,
        commandLine: String?,
        port: Int,
        note: String? = nil
    ) -> AddSuggestedProfileResult {
        guard let commandLine else {
            return .invalid(reason: "当前进程未暴露命令行，无法自动生成启动命令。")
        }
        let normalizedCommand = normalizeCommandLine(commandLine)
        guard !normalizedCommand.isEmpty else {
            return .invalid(reason: "当前进程未暴露命令行，无法自动生成启动命令。")
        }
        let normalizedNote = note?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty

        do {
            var allProfiles = try yamlStore.loadProfiles()

            if let existingIndex = allProfiles.firstIndex(where: {
                normalizeCommandLine($0.command) == normalizedCommand
            }) {
                let existing = allProfiles[existingIndex]
                if normalizedNote != existing.note {
                    let updated = CommandProfile(
                        id: existing.id,
                        name: existing.name,
                        note: normalizedNote,
                        cwd: existing.cwd,
                        command: existing.command,
                        ports: existing.ports,
                        tags: existing.tags,
                        env: existing.env
                    )
                    allProfiles[existingIndex] = updated
                    try yamlStore.saveProfiles(allProfiles)
                    profiles = allProfiles.sorted(by: sortProfiles)
                    lastErrorMessage = nil
                    appendEvent(level: .info, message: "已更新启动命令说明：\(existing.name)。")
                    return .updated(name: existing.name)
                }
                return .duplicate(name: existing.name)
            }

            let guessedCWD = guessWorkingDirectory(from: normalizedCommand) ?? NSHomeDirectory()
            let normalizedName = sanitizeProfileName(preferredName, fallbackPort: port)

            let profile = CommandProfile(
                name: normalizedName,
                note: normalizedNote,
                cwd: guessedCWD,
                command: normalizedCommand,
                ports: port > 0 ? [port] : [],
                tags: ["suggested"]
            )
            allProfiles.append(profile)

            try yamlStore.saveProfiles(allProfiles)
            profiles = allProfiles.sorted(by: sortProfiles)
            lastErrorMessage = nil
            removeDismissedSuggestion(for: normalizedCommand)
            appendEvent(level: .info, message: "已新增启动命令：\(profile.name)。")

            return .added(name: profile.name)
        } catch {
            return .failed(reason: "写入 profiles.yaml 失败：\(error.localizedDescription)")
        }
    }

    func shouldSuggestProfile(commandLine: String?) -> Bool {
        guard let commandLine else { return false }
        let normalized = normalizeCommandLine(commandLine)
        guard !normalized.isEmpty else { return false }
        guard !hasProfile(commandLine: normalized) else { return false }
        return !dismissedSuggestionSignatures.contains(commandSignature(for: normalized))
    }

    func dismissSuggestion(for commandLine: String?) {
        guard let commandLine else { return }
        let normalized = normalizeCommandLine(commandLine)
        guard !normalized.isEmpty else { return }
        dismissedSuggestionSignatures.insert(commandSignature(for: normalized))
        persistDismissedSuggestionSignatures()
    }

    func inferredPort(for profile: CommandProfile) -> Int? {
        inferredPort(from: profile)
    }

    func rebindPort(
        for profile: CommandProfile,
        to newPort: Int,
        restartIfRunning: Bool
    ) async -> RebindPortResult {
        guard (1...65_535).contains(newPort) else {
            return .invalid(reason: "端口必须在 1-65535 之间。")
        }

        guard let targetIndex = profiles.firstIndex(where: { $0.id == profile.id }) else {
            return .invalid(reason: "未找到目标启动命令，请先重载配置。")
        }

        let original = profiles[targetIndex]
        guard let oldPort = inferredPort(from: original) else {
            return .invalid(reason: "无法从当前命令中识别端口，请手动编辑 YAML。")
        }

        guard oldPort != newPort else {
            return .unchanged(reason: "端口没有变化。")
        }

        let commandRewrite = rewriteCommandPort(
            in: original.command,
            oldPort: oldPort,
            newPort: newPort
        )
        let frameworkTemplateRewrite = rewriteCommandUsingFrameworkTemplate(
            in: original.command,
            newPort: newPort
        )
        let envRewrite = rewriteEnvironmentPort(
            env: original.env,
            oldPort: oldPort,
            newPort: newPort
        )

        let strategy: RebindPortStrategy
        let rewrittenCommand: String
        let rewrittenEnvironment: [String: String]

        if let commandRewrite {
            strategy = .commandArgument
            rewrittenCommand = commandRewrite
            rewrittenEnvironment = original.env
        } else if let frameworkTemplateRewrite {
            strategy = frameworkTemplateRewrite.strategy
            rewrittenCommand = frameworkTemplateRewrite.command
            rewrittenEnvironment = original.env
        } else if envRewrite.didChange {
            strategy = envRewrite.injected ? .injectedPortEnvironment : .existingPortEnvironment
            rewrittenCommand = original.command
            rewrittenEnvironment = envRewrite.env
        } else {
            var injectedEnv = original.env
            injectedEnv["PORT"] = String(newPort)
            strategy = .injectedPortEnvironment
            rewrittenCommand = original.command
            rewrittenEnvironment = injectedEnv
        }

        let updatedPorts = rewritePorts(
            currentPorts: original.ports,
            oldPort: oldPort,
            newPort: newPort
        )

        let updated = CommandProfile(
            id: original.id,
            name: original.name,
            note: original.note,
            cwd: original.cwd,
            command: rewrittenCommand,
            ports: updatedPorts,
            tags: original.tags,
            env: rewrittenEnvironment
        )

        var nextProfiles = profiles
        nextProfiles[targetIndex] = updated

        do {
            try yamlStore.saveProfiles(nextProfiles)
            profiles = nextProfiles.sorted(by: sortProfiles)
            lastErrorMessage = nil
            appendEvent(level: .info, message: "已更新端口：\(updated.name) \(oldPort) → \(newPort)。", profileName: updated.name)
        } catch {
            return .failed(reason: "保存 profiles.yaml 失败：\(error.localizedDescription)")
        }

        let shouldRestart = restartIfRunning && (runningByProfileID[original.id] != nil)
        if shouldRestart {
            await stop(profile: original)
            start(profile: updated)
        }

        return .updated(
            name: updated.name,
            oldPort: oldPort,
            newPort: newPort,
            restarted: shouldRestart,
            strategy: strategy
        )
    }

    private func hasProfile(commandLine: String) -> Bool {
        let normalized = normalizeCommandLine(commandLine)
        return profiles.contains { profile in
            normalizeCommandLine(profile.command) == normalized
        }
    }

    private func removeDismissedSuggestion(for commandLine: String) {
        dismissedSuggestionSignatures.remove(commandSignature(for: commandLine))
        persistDismissedSuggestionSignatures()
    }

    private func inferredPort(from profile: CommandProfile) -> Int? {
        if let declared = profile.ports.first(where: { $0 > 0 }) {
            return declared
        }

        let command = profile.command
        let patterns = [
            "--port(?:=|\\s+)(\\d{1,5})",
            "(?:^|\\s)-p\\s+(\\d{1,5})",
            "\\bPORT\\s*=\\s*(\\d{1,5})\\b",
            "localhost:(\\d{1,5})",
            "127\\.0\\.0\\.1:(\\d{1,5})",
            ":(\\d{2,5})\\b"
        ]

        for pattern in patterns {
            guard let values = capturedIntegers(
                in: command,
                pattern: pattern
            ) else { continue }

            if let port = values.first(where: { (1...65_535).contains($0) }) {
                return port
            }
        }

        return nil
    }

    private func rewritePorts(
        currentPorts: [Int],
        oldPort: Int,
        newPort: Int
    ) -> [Int] {
        if currentPorts.isEmpty {
            return [newPort]
        }

        var replaced = false
        var rewritten = currentPorts.map { value -> Int in
            if value == oldPort {
                replaced = true
                return newPort
            }
            return value
        }

        if !replaced {
            rewritten.append(newPort)
        }

        let unique = Array(Set(rewritten.filter { $0 > 0 })).sorted()
        return unique.isEmpty ? [newPort] : unique
    }

    private func rewriteCommandPort(
        in command: String,
        oldPort: Int,
        newPort: Int
    ) -> String? {
        let escapedOld = NSRegularExpression.escapedPattern(for: String(oldPort))

        let strictPatterns: [String] = [
            "(--port\\s+)\(escapedOld)(\\b)",
            "(--port=)\(escapedOld)(\\b)",
            "(-p\\s+)\(escapedOld)(\\b)",
            "(\\bPORT\\s*=\\s*)\(escapedOld)(\\b)",
            "(localhost:)\(escapedOld)(\\b)",
            "(127\\.0\\.0\\.1:)\(escapedOld)(\\b)"
        ]

        var rewritten = command
        var replacedCount = 0
        for pattern in strictPatterns {
            let result = replacing(
                in: rewritten,
                pattern: pattern,
                with: "$1\(newPort)$2"
            )
            rewritten = result.text
            replacedCount += result.count
        }

        if replacedCount == 0 {
            let commonResult = replaceCommonPortArguments(
                in: rewritten,
                newPort: newPort
            )
            rewritten = commonResult.text
            replacedCount += commonResult.count
        }

        if replacedCount == 0 {
            let relaxed = replacing(
                in: rewritten,
                pattern: "(:)\(escapedOld)(\\b)",
                with: "$1\(newPort)$2"
            )
            rewritten = relaxed.text
            replacedCount += relaxed.count
        }

        guard replacedCount > 0 else { return nil }
        return rewritten
    }

    private func rewriteCommandUsingFrameworkTemplate(
        in command: String,
        newPort: Int
    ) -> (command: String, strategy: RebindPortStrategy)? {
        let lower = command.lowercased()

        let commonResult = replaceCommonPortArguments(in: command, newPort: newPort)
        if commonResult.count > 0 {
            return (commonResult.text, .frameworkTemplate)
        }

        if isNextCommand(lower) {
            return ("\(command) -p \(newPort)", .frameworkTemplate)
        }

        if isViteFamilyCommand(lower) {
            return ("\(command) --port \(newPort)", .frameworkTemplate)
        }

        if isUvicornFamilyCommand(lower) {
            return ("\(command) --port \(newPort)", .frameworkTemplate)
        }

        if isPackageManagerScriptCommand(lower) {
            return (
                appendPackageScriptPortArgument(
                    command,
                    lowercased: lower,
                    newPort: newPort
                ),
                .packageScriptArgument
            )
        }

        return nil
    }

    private func replaceCommonPortArguments(
        in command: String,
        newPort: Int
    ) -> (text: String, count: Int) {
        let patterns: [String] = [
            "(--port\\s+)(\\d{1,5})",
            "(--port=)(\\d{1,5})",
            "(-p\\s+)(\\d{1,5})"
        ]

        var rewritten = command
        var replacedCount = 0
        for pattern in patterns {
            let result = replacing(
                in: rewritten,
                pattern: pattern,
                with: "$1\(newPort)"
            )
            rewritten = result.text
            replacedCount += result.count
        }

        return (rewritten, replacedCount)
    }

    private func isNextCommand(_ lowercased: String) -> Bool {
        lowercased.contains("next dev") || lowercased.contains("next start")
    }

    private func isViteFamilyCommand(_ lowercased: String) -> Bool {
        lowercased.contains("vite")
            || lowercased.contains("nuxt")
            || lowercased.contains("astro dev")
            || lowercased.contains("webpack-dev-server")
            || lowercased.contains("svelte-kit dev")
    }

    private func isUvicornFamilyCommand(_ lowercased: String) -> Bool {
        lowercased.contains("uvicorn") || lowercased.contains("gunicorn")
    }

    private func isPackageManagerScriptCommand(_ lowercased: String) -> Bool {
        lowercased.contains("npm run ")
            || lowercased.contains("pnpm run ")
            || lowercased.contains("yarn ")
            || lowercased.contains("bun run ")
    }

    private func appendPackageScriptPortArgument(
        _ command: String,
        lowercased: String,
        newPort: Int
    ) -> String {
        if lowercased.contains("npm run ")
            || lowercased.contains("pnpm run ")
            || lowercased.contains("bun run ")
            || lowercased.contains("yarn run ") {
            return "\(command) -- --port \(newPort)"
        }

        if lowercased.contains("yarn ") {
            return "\(command) --port \(newPort)"
        }

        return "\(command) -- --port \(newPort)"
    }

    private func rewriteEnvironmentPort(
        env: [String: String],
        oldPort: Int,
        newPort: Int
    ) -> (env: [String: String], didChange: Bool, injected: Bool) {
        guard !env.isEmpty else {
            return (env, false, false)
        }

        let oldValue = String(oldPort)
        let newValue = String(newPort)
        var nextEnv = env
        var changed = false

        for key in env.keys.sorted() {
            let upperKey = key.uppercased()
            guard upperKey.contains("PORT") else { continue }

            if env[key] == oldValue {
                nextEnv[key] = newValue
                changed = true
            }
        }

        if changed {
            return (nextEnv, true, false)
        }

        if let currentPort = env["PORT"], currentPort != newValue {
            nextEnv["PORT"] = newValue
            return (nextEnv, true, false)
        }

        return (env, false, false)
    }

    private func capturedIntegers(
        in text: String,
        pattern: String
    ) -> [Int]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: range)
        guard !matches.isEmpty else { return nil }

        return matches.compactMap { match in
            guard match.numberOfRanges >= 2 else { return nil }
            let groupRange = match.range(at: 1)
            guard let swiftRange = Range(groupRange, in: text) else { return nil }
            return Int(text[swiftRange])
        }
    }

    private func replacing(
        in text: String,
        pattern: String,
        with template: String
    ) -> (text: String, count: Int) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return (text, 0)
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let count = regex.numberOfMatches(in: text, range: range)
        guard count > 0 else { return (text, 0) }
        let replaced = regex.stringByReplacingMatches(
            in: text,
            range: range,
            withTemplate: template
        )
        return (replaced, count)
    }

    private func persistDismissedSuggestionSignatures() {
        defaults.set(
            Array(dismissedSuggestionSignatures).sorted(),
            forKey: Keys.dismissedSuggestionSignatures
        )
    }

    private func handleProcessTerminated(for profileID: String) {
        let profileName = profiles.first(where: { $0.id == profileID })?.name
        managedProcesses.removeValue(forKey: profileID)
        runningByProfileID.removeValue(forKey: profileID)
        stoppingProfileIDs.remove(profileID)
        appendEvent(level: .info, message: "进程已退出。", profileName: profileName)
    }

    private func appendEvent(
        level: CommandEvent.Level,
        message: String,
        profileName: String? = nil
    ) {
        recentEvents.append(
            CommandEvent(level: level, message: message, profileName: profileName)
        )

        let maxCount = 200
        if recentEvents.count > maxCount {
            recentEvents.removeFirst(recentEvents.count - maxCount)
        }
    }

    private func makeManagedProcess(for profile: CommandProfile) throws -> ManagedProcess {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", profile.command]
        process.currentDirectoryURL = URL(fileURLWithPath: profile.cwd)

        var environment = ProcessInfo.processInfo.environment
        for (key, value) in profile.env {
            environment[key] = value
        }
        process.environment = environment

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        stdout.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }

        return ManagedProcess(
            process: process,
            stdoutPipe: stdout,
            stderrPipe: stderr
        )
    }

    private func terminateManagedProcess(_ managed: ManagedProcess) async {
        let process = managed.process
        guard process.isRunning else { return }

        process.terminate()
        let deadline = Date().addingTimeInterval(1.1)

        while process.isRunning, Date() < deadline {
            try? await Task.sleep(nanoseconds: 60_000_000)
        }

        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }

        if process.isRunning {
            process.waitUntilExit()
        }
    }

    private func sanitizeProfileName(_ name: String, fallbackPort: Int) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        return fallbackPort > 0 ? "service-\(fallbackPort)" : "service"
    }

    private func normalizedProfilesKeepingAtMostOneMock(_ input: [CommandProfile]) -> [CommandProfile] {
        var selectedMock: CommandProfile?
        var userProfiles: [CommandProfile] = []

        for profile in input {
            if isMockProfileDefinition(profile) {
                if selectedMock == nil {
                    selectedMock = ensureMockTag(profile)
                }
            } else {
                userProfiles.append(profile)
            }
        }

        if let selectedMock {
            return ([selectedMock] + userProfiles).sorted(by: sortProfiles)
        }
        return userProfiles.sorted(by: sortProfiles)
    }

    private func isMockProfileDefinition(_ profile: CommandProfile) -> Bool {
        if profile.tags.contains(where: { $0.lowercased() == "mock" }) {
            return true
        }
        return profile.name.lowercased() == "admin-api"
    }

    private func ensureMockTag(_ profile: CommandProfile) -> CommandProfile {
        guard !profile.tags.contains(where: { $0.lowercased() == "mock" }) else {
            return profile
        }

        return CommandProfile(
            id: profile.id,
            name: profile.name,
            note: profile.note,
            cwd: profile.cwd,
            command: profile.command,
            ports: profile.ports,
            tags: profile.tags + ["mock"],
            env: profile.env
        )
    }

    private func sortProfiles(_ lhs: CommandProfile, _ rhs: CommandProfile) -> Bool {
        lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }

    private func guessWorkingDirectory(from commandLine: String) -> String? {
        let tokens = commandLine
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)

        for rawToken in tokens {
            let token = rawToken.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            guard token.contains("/") else { continue }
            if token.contains("@") { continue }

            let path: String
            if token.contains("=") {
                let split = token.split(separator: "=", maxSplits: 1).map(String.init)
                guard split.count == 2 else { continue }
                path = split[1]
            } else {
                path = token
            }

            let expanded = (path as NSString).expandingTildeInPath
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory) {
                if isDirectory.boolValue {
                    return expanded
                }
                return URL(fileURLWithPath: expanded).deletingLastPathComponent().path
            }
        }

        return nil
    }

    private func normalizeCommandLine(_ commandLine: String) -> String {
        commandLine
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(
                of: "\\s+",
                with: " ",
                options: .regularExpression
            )
    }

    private func commandSignature(for commandLine: String) -> String {
        let normalized = normalizeCommandLine(commandLine).lowercased()
        var hash: UInt64 = 1469598103934665603
        for byte in normalized.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return String(hash, radix: 16)
    }
}

private struct ManagedProcess {
    let process: Process
    let stdoutPipe: Pipe
    let stderrPipe: Pipe
}

struct CommandProfilesYAMLStore {
    private struct Draft {
        var id: String?
        var name: String = ""
        var note: String?
        var cwd: String = ""
        var command: String = ""
        var ports: [Int] = []
        var tags: [String] = []
        var env: [String: String] = [:]
    }

    private let fileManager = FileManager.default

    var fileURL: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return appSupport
            .appendingPathComponent("PortPilot", isDirectory: true)
            .appendingPathComponent("profiles.yaml")
    }

    func ensureFileExists() throws {
        let folder = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)

        guard !fileManager.fileExists(atPath: fileURL.path) else { return }
        let template = defaultTemplate()
        try template.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    func loadProfiles() throws -> [CommandProfile] {
        try ensureFileExists()
        let text = try String(contentsOf: fileURL, encoding: .utf8)
        return parse(text: text).sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    func saveProfiles(_ profiles: [CommandProfile]) throws {
        try ensureFileExists()
        let serialized = serialize(profiles: profiles)
        try serialized.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private func parse(text: String) -> [CommandProfile] {
        let lines = text.components(separatedBy: .newlines)
        var profiles: [CommandProfile] = []
        var draft: Draft?
        var envIndent: Int?

        func flushDraft() {
            guard let current = draft else { return }
            guard !current.name.isEmpty, !current.command.isEmpty else {
                draft = nil
                envIndent = nil
                return
            }

            let cwd = current.cwd.isEmpty ? NSHomeDirectory() : (current.cwd as NSString).expandingTildeInPath
            profiles.append(
                CommandProfile(
                    id: current.id,
                    name: current.name,
                    note: current.note,
                    cwd: cwd,
                    command: current.command,
                    ports: current.ports,
                    tags: current.tags,
                    env: current.env
                )
            )
            draft = nil
            envIndent = nil
        }

        for rawLine in lines {
            let indent = leadingSpaces(in: rawLine)
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }

            if trimmed == "profiles:" {
                continue
            }

            if trimmed.hasPrefix("- ") {
                flushDraft()
                draft = Draft()
                let remainder = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if let (key, value) = splitKeyValue(remainder) {
                    if var current = draft {
                        assign(key: key, value: value, to: &current, envIndent: &envIndent, indent: indent)
                        draft = current
                    }
                }
                continue
            }

            guard draft != nil else { continue }

            if let envIndent, indent > envIndent {
                if let (key, value) = splitKeyValue(trimmed) {
                    if var current = draft {
                        current.env[key] = unquote(value)
                        draft = current
                    }
                }
                continue
            } else {
                envIndent = nil
            }

            if let (key, value) = splitKeyValue(trimmed) {
                if var current = draft {
                    assign(key: key, value: value, to: &current, envIndent: &envIndent, indent: indent)
                    draft = current
                }
            }
        }

        flushDraft()
        return profiles
    }

    private func assign(
        key: String,
        value: String,
        to draft: inout Draft,
        envIndent: inout Int?,
        indent: Int
    ) {
        switch key {
        case "id":
            draft.id = unquote(value)
        case "name":
            draft.name = unquote(value)
        case "note":
            draft.note = unquote(value)
        case "cwd":
            draft.cwd = unquote(value)
        case "command":
            draft.command = unquote(value)
        case "ports":
            draft.ports = parseIntList(value)
        case "tags":
            draft.tags = parseStringList(value)
        case "env":
            envIndent = indent
        default:
            break
        }
    }

    private func serialize(profiles: [CommandProfile]) -> String {
        var lines: [String] = []
        lines.append("profiles:")

        for profile in profiles.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) {
            lines.append("  - id: \(yamlScalar(profile.id))")
            lines.append("    name: \(yamlScalar(profile.name))")
            if let note = profile.note, !note.isEmpty {
                lines.append("    note: \(yamlScalar(note))")
            }
            lines.append("    cwd: \(yamlScalar(profile.cwd))")
            lines.append("    command: \(yamlScalar(profile.command))")
            lines.append("    ports: [\(profile.ports.map(String.init).joined(separator: ", "))]")

            if !profile.tags.isEmpty {
                lines.append("    tags: [\(profile.tags.map(yamlScalar).joined(separator: ", "))]")
            }

            if !profile.env.isEmpty {
                lines.append("    env:")
                for key in profile.env.keys.sorted() {
                    let value = profile.env[key] ?? ""
                    lines.append("      \(key): \(yamlScalar(value))")
                }
            }
        }

        if lines.count == 1 {
            lines.append("  # Add your first profile here")
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private func defaultTemplate() -> String {
        """
        profiles:
          - name: "admin-api"
            cwd: "~/work/admin-api"
            command: "pnpm dev"
            ports: [3001]
            tags: ["workspace:admin", "mock"]
        """
    }

    private func splitKeyValue(_ line: String) -> (String, String)? {
        let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        return (key, value)
    }

    private func parseIntList(_ raw: String) -> [Int] {
        parseStringList(raw)
            .compactMap(Int.init)
            .filter { $0 > 0 }
    }

    private func parseStringList(_ raw: String) -> [String] {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("[") && value.hasSuffix("]") {
            value = String(value.dropFirst().dropLast())
        }

        return value
            .split(separator: ",")
            .map { unquote(String($0).trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.isEmpty }
    }

    private func unquote(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return trimmed }

        if (trimmed.hasPrefix("\"") && trimmed.hasSuffix("\""))
            || (trimmed.hasPrefix("'") && trimmed.hasSuffix("'")) {
            let inner = String(trimmed.dropFirst().dropLast())
            return inner.replacingOccurrences(of: "\\\"", with: "\"")
        }

        return trimmed
    }

    private func yamlScalar(_ value: String) -> String {
        let mustQuote = value.contains(":")
            || value.contains("#")
            || value.contains("[")
            || value.contains("]")
            || value.contains(",")
            || value.contains(" ")
            || value.isEmpty

        guard mustQuote else { return value }
        let escaped = value.replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private func leadingSpaces(in line: String) -> Int {
        line.prefix { $0 == " " || $0 == "\t" }.count
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}

private enum Keys {
    static let dismissedSuggestionSignatures = "commands.dismissedSuggestionSignatures"
}
