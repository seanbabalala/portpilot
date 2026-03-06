import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct PortsView: View {
    private static let allWorkspaceToken = "__all__"

    private enum SortMode: String, CaseIterable, Identifiable {
        case byPort
        case byProcess
        case byRecent

        var id: String { rawValue }

        func label(language: AppLanguage) -> String {
            switch (self, language) {
            case (.byPort, .chinese):
                return "端口"
            case (.byPort, .english):
                return "Port"
            case (.byProcess, .chinese):
                return "进程"
            case (.byProcess, .english):
                return "Process"
            case (.byRecent, .chinese):
                return "最近"
            case (.byRecent, .english):
                return "Recent"
            }
        }
    }

    private enum BentoTone {
        case pearl
        case sky
        case mint
        case peach
    }

    private enum SettingsFocusPanel: String, CaseIterable, Hashable {
        case overview
        case filters
        case commands
        case ports
        case trend

        func title(language: AppLanguage) -> String {
            switch self {
            case .overview:
                return language == .english ? "Overview" : "概览指标"
            case .filters:
                return language == .english ? "Filters & Search" : "筛选与搜索"
            case .commands:
                return language == .english ? "Startup Commands" : "启动命令"
            case .ports:
                return language == .english ? "Port List" : "端口列表"
            case .trend:
                return language == .english ? "Trend Chart" : "趋势图"
            }
        }

        var symbol: String {
            switch self {
            case .overview:
                return "square.grid.2x2"
            case .filters:
                return "line.3.horizontal.decrease.circle"
            case .commands:
                return "terminal"
            case .ports:
                return "dot.radiowaves.left.and.right"
            case .trend:
                return "chart.line.uptrend.xyaxis"
            }
        }

        var tone: BentoTone {
            switch self {
            case .overview:
                return .pearl
            case .filters:
                return .sky
            case .commands:
                return .mint
            case .ports:
                return .peach
            case .trend:
                return .sky
            }
        }
    }

    private struct FocusHeaderButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.985 : 1)
                .opacity(configuration.isPressed ? 0.95 : 1)
                .animation(
                    .spring(response: 0.22, dampingFraction: 0.78),
                    value: configuration.isPressed
                )
        }
    }

    private struct PortHistoryPoint: Identifiable {
        let id = UUID()
        let time: Date
        let value: Double
    }

    private struct KillFeedback: Identifiable {
        let id = UUID()
        let message: String
        let isError: Bool
    }

    private struct AutoProfileSuggestion: Identifiable {
        let id = UUID()
        let item: PortsStore.ListenerItem
        let suggestedName: String
    }

    private struct ConflictFixSuggestion: Identifiable {
        let id: String
        let conflictPort: Int
        let profile: CommandProfile
        let suggestedPort: Int
        let participantCount: Int
    }

    private struct SettingChoice<Value: Hashable>: Identifiable {
        let id: String
        let title: String
        let value: Value
    }

    @ObservedObject var store: PortsStore
    @ObservedObject var settings: SettingsStore
    @ObservedObject var scanner: PortsScanner
    @ObservedObject var commands: CommandProfilesStore
    @ObservedObject var knowledge: PortKnowledgeStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var searchText: String = ""
    @State private var sortMode: SortMode = .byPort
    @State private var history: [PortHistoryPoint] = []
    @State private var isSettingsExpanded: Bool = false
    @State private var expandedItemID: String?
    @State private var pendingKillItem: PortsStore.ListenerItem?
    @State private var pendingAutoProfileSuggestion: AutoProfileSuggestion?
    @State private var pendingPortEditProfile: CommandProfile?
    @State private var pendingConflictFixSuggestion: ConflictFixSuggestion?
    @State private var pendingInsightItem: PortsStore.ListenerItem?
    @State private var pendingPortEditValue: String = ""
    @State private var pendingPortEditRestart: Bool = true
    @State private var pendingInsightLabel: String = ""
    @State private var pendingInsightPurpose: String = ""
    @State private var pendingInsightScope: PortKnowledgeStore.MatchScope = .processPort
    @State private var portEditInFlight: Bool = false
    @State private var killFeedback: KillFeedback?
    @State private var killFeedbackTask: Task<Void, Never>?
    @State private var portHealthCheckTask: Task<Void, Never>?
    @State private var killInFlightPID: Int?
    @State private var selectedWorkspaceID: String = Self.allWorkspaceToken
    @State private var settingsFocusedExpandedPanel: SettingsFocusPanel?
    @State private var hoveredSettingsPanel: SettingsFocusPanel?

    private func tr(_ chinese: String, _ english: String) -> String {
        settings.tr(chinese, english)
    }

    private var query: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isFiltering: Bool {
        !query.isEmpty
    }

    private var filteredListeners: [PortsStore.ListenerItem] {
        let filtered = store.listeners.filter { item in
            guard !query.isEmpty else { return true }

            let profile = resolvedFriendlyProfile(for: item)
            return item.processName.localizedCaseInsensitiveContains(query)
                || item.displayName.localizedCaseInsensitiveContains(query)
                || String(item.port).contains(query)
                || String(item.pid).contains(query)
                || (item.user?.localizedCaseInsensitiveContains(query) ?? false)
                || profile.title.localizedCaseInsensitiveContains(query)
                || profile.subtitle.localizedCaseInsensitiveContains(query)
                || (settings.showCommandLine && (item.commandLine?.localizedCaseInsensitiveContains(query) ?? false))
        }

        return sort(filtered)
    }

    private var uniquePortCount: Int {
        Set(filteredListeners.map(\.port)).count
    }

    private var totalUniquePortCount: Int {
        Set(store.listeners.map(\.port)).count
    }

    private var currentOccupiedPortCount: Int {
        isFiltering ? uniquePortCount : totalUniquePortCount
    }

    private var statusText: String {
        if scanner.isUnknown { return tr("状态异常", "Status Warning") }
        return tr("运行正常", "Running")
    }

    private var statusTint: Color {
        scanner.isUnknown ? .orange : Color(red: 0.12, green: 0.66, blue: 0.45)
    }

    private var countLabel: String {
        if isFiltering {
            return tr(
                "\(filteredListeners.count) / \(store.listeners.count) 项",
                "\(filteredListeners.count) / \(store.listeners.count) items"
            )
        }
        return tr("\(filteredListeners.count) 项", "\(filteredListeners.count) items")
    }

    private var isCompactScreen: Bool {
        (NSScreen.main?.visibleFrame.height ?? 900) < 920
    }

    private var listHeight: CGFloat {
        isSettingsExpanded ? 170 : 258
    }

    private var commandProfilesListMaxHeight: CGFloat {
        isCompactScreen ? 192 : 232
    }

    private var metricsPairHeight: CGFloat {
        isCompactScreen ? 104 : 110
    }

    private var metricsCardContentHeight: CGFloat {
        max(metricsPairHeight - 20, 88)
    }

    private var heroContentMinHeight: CGFloat {
        isCompactScreen ? 92 : 98
    }

    private var headerGaugeSize: CGSize {
        isCompactScreen ? CGSize(width: 74, height: 54) : CGSize(width: 78, height: 57)
    }

    private var lastScanText: String {
        guard let lastScanAt = scanner.lastSuccessfulScanAt else {
            return tr("等待首次扫描", "Waiting for first scan")
        }
        return lastScanAt.formatted(date: .omitted, time: .standard)
    }

    private var modeText: String {
        switch settings.countMode {
        case .portAndPID:
            return tr("按实例", "By Instance")
        case .portOnly:
            return tr("按端口", "By Port")
        }
    }

    private var workspaceOptions: [String] {
        [Self.allWorkspaceToken] + commands.workspaceNames
    }

    private var selectedWorkspaceName: String? {
        selectedWorkspaceID == Self.allWorkspaceToken ? nil : selectedWorkspaceID
    }

    private var selectedWorkspaceTitle: String {
        if selectedWorkspaceID == Self.allWorkspaceToken {
            return tr("全部场景", "All Workspaces")
        }
        return selectedWorkspaceID
    }

    private var scopedProfiles: [CommandProfile] {
        commands.profiles(inWorkspace: selectedWorkspaceName)
    }

    private var scopedRunningCount: Int {
        scopedProfiles.filter { commands.isRunning($0) }.count
    }

    private var detectedExternalRunningPIDByProfileID: [String: Int] {
        let managedProfileIDs = Set(commands.runningByProfileID.keys)
        let managedPIDs = Set(commands.runningByProfileID.values.map { Int($0.pid) })

        let externalListeners = store.listeners.filter { listener in
            !managedPIDs.contains(listener.pid)
        }

        var commandToPID: [String: Int] = [:]
        var portToPID: [Int: Int] = [:]

        for item in externalListeners.sorted(by: { lhs, rhs in
            if lhs.port == rhs.port {
                return lhs.pid < rhs.pid
            }
            return lhs.port < rhs.port
        }) {
            if let commandLine = item.commandLine {
                let normalized = normalizeCommandForMatch(commandLine)
                if !normalized.isEmpty, commandToPID[normalized] == nil {
                    commandToPID[normalized] = item.pid
                }
            }
            if portToPID[item.port] == nil {
                portToPID[item.port] = item.pid
            }
        }

        var result: [String: Int] = [:]
        for profile in commands.profiles {
            guard !managedProfileIDs.contains(profile.id) else { continue }

            let normalizedCommand = normalizeCommandForMatch(profile.command)
            if let pid = commandToPID[normalizedCommand] {
                result[profile.id] = pid
                continue
            }

            guard let inferredPort = commands.inferredPort(for: profile) else { continue }
            if let pid = portToPID[inferredPort] {
                result[profile.id] = pid
            }
        }

        return result
    }

    private var scopedStartableCount: Int {
        scopedProfiles.filter { !isProfileActive($0) }.count
    }

    private var conflictFixSuggestions: [ConflictFixSuggestion] {
        let groupedByPort = Dictionary(grouping: store.listeners, by: \.port)
        let conflictGroups = groupedByPort.filter { _, listeners in
            Set(listeners.map(\.pid)).count > 1
        }

        guard !conflictGroups.isEmpty else { return [] }

        let profileByID = Dictionary(uniqueKeysWithValues: commands.profiles.map { ($0.id, $0) })
        let profileByPID: [Int: CommandProfile] = Dictionary(
            uniqueKeysWithValues: commands.runningByProfileID.values.compactMap { running in
                guard let profile = profileByID[running.profileID] else { return nil }
                return (Int(running.pid), profile)
            }
        )

        var reservedPorts = Set(store.listeners.map(\.port))
        var suggestions: [ConflictFixSuggestion] = []

        for conflictPort in conflictGroups.keys.sorted() {
            guard let listeners = conflictGroups[conflictPort] else { continue }
            let uniquePIDs = Array(Set(listeners.map(\.pid))).sorted()

            let managedProfiles = uniquePIDs.compactMap { pid in
                profileByPID[pid]
            }
            .reduce(into: [String: CommandProfile]()) { partialResult, profile in
                partialResult[profile.id] = profile
            }
            .values
            .sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }

            for profile in managedProfiles {
                let preferred = max(conflictPort + 1, 1024)
                guard let suggestedPort = nextAvailablePort(
                    startingAt: preferred,
                    occupied: reservedPorts
                ) else { continue }

                reservedPorts.insert(suggestedPort)
                suggestions.append(
                    ConflictFixSuggestion(
                        id: "\(profile.id)::\(conflictPort)::\(suggestedPort)",
                        conflictPort: conflictPort,
                        profile: profile,
                        suggestedPort: suggestedPort,
                        participantCount: uniquePIDs.count
                    )
                )
            }
        }

        return suggestions
    }

    private var unmanagedConflictPorts: [Int] {
        let groupedByPort = Dictionary(grouping: store.listeners, by: \.port)
        let conflictPorts = groupedByPort.compactMap { port, listeners -> Int? in
            Set(listeners.map(\.pid)).count > 1 ? port : nil
        }

        guard !conflictPorts.isEmpty else { return [] }

        let managedPIDs = Set(commands.runningByProfileID.values.map { Int($0.pid) })
        let managedConflictPorts = Set(
            store.listeners
                .filter { managedPIDs.contains($0.pid) }
                .map(\.port)
        )

        return conflictPorts.filter { !managedConflictPorts.contains($0) }.sorted()
    }

    private var isDarkMode: Bool {
        colorScheme == .dark
    }

    private var panelStrokeColor: Color {
        isDarkMode ? Color.white.opacity(0.24) : Color.white.opacity(0.82)
    }

    private var panelInnerStrokeColor: Color {
        isDarkMode ? Color.black.opacity(0.26) : Color.black.opacity(0.06)
    }

    private var panelSwitchAnimation: Animation {
        reduceMotion
            ? .linear(duration: 0.08)
            : .spring(response: 0.3, dampingFraction: 0.9, blendDuration: 0.1)
    }

    private var sectionExpandAnimation: Animation {
        reduceMotion ? .linear(duration: 0.07) : .easeInOut(duration: 0.14)
    }

    private var feedbackBannerAnimation: Animation {
        reduceMotion ? .linear(duration: 0.08) : .easeInOut(duration: 0.18)
    }

    private var shouldUseScrollablePanelContainer: Bool {
        isSettingsExpanded && isCompactScreen
    }

    private var panelContainerHeight: CGFloat {
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 900
        return max(520, min(860, screenHeight - 86))
    }

    var body: some View {
        ZStack {
            backgroundLayer
            if shouldUseScrollablePanelContainer {
                ScrollView(.vertical) {
                    panel
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                }
                .unifiedScrollVisual(isDarkMode: isDarkMode)
                .frame(height: panelContainerHeight)
            } else {
                panel
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
            }

            if let pendingKillItem {
                killConfirmOverlay(for: pendingKillItem)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .zIndex(10)
            }

            if let pendingInsightItem {
                insightEditorOverlay(for: pendingInsightItem)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .zIndex(10)
            }

            if let pendingAutoProfileSuggestion {
                autoProfileSuggestionOverlay(pendingAutoProfileSuggestion)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .zIndex(9)
            }

            if let pendingPortEditProfile {
                portEditOverlay(for: pendingPortEditProfile)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .zIndex(10)
            }

            if let pendingConflictFixSuggestion {
                conflictFixConfirmOverlay(for: pendingConflictFixSuggestion)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .zIndex(10)
            }
        }
        .frame(width: 396)
        .onAppear {
            seedHistoryIfNeeded()
            appendHistoryPoint(force: true)
        }
        .onChange(of: store.listeners) {
            appendHistoryPoint()
            if let expandedItemID,
               !store.listeners.contains(where: { $0.id == expandedItemID }) {
                self.expandedItemID = nil
            }

            if let pendingInsightItem,
               !store.listeners.contains(where: { $0.id == pendingInsightItem.id }) {
                self.pendingInsightItem = nil
            }

            if let pendingConflictFixSuggestion,
               !conflictFixSuggestions.contains(where: { $0.id == pendingConflictFixSuggestion.id }) {
                self.pendingConflictFixSuggestion = nil
            }

            evaluateAutoProfileSuggestion(in: store.listeners)
        }
        .onChange(of: settings.autoSuggestProfiles) {
            if !settings.autoSuggestProfiles {
                pendingAutoProfileSuggestion = nil
            } else {
                evaluateAutoProfileSuggestion(in: store.listeners)
            }
        }
        .onChange(of: commands.profiles) {
            let valid = Set(workspaceOptions)
            if !valid.contains(selectedWorkspaceID) {
                selectedWorkspaceID = Self.allWorkspaceToken
            }
        }
        .onChange(of: isSettingsExpanded) {
            if isSettingsExpanded {
                settingsFocusedExpandedPanel = nil
            }
            hoveredSettingsPanel = nil
        }
        .onChange(of: pendingInsightScope) {
            guard let pendingInsightItem else { return }
            let entry = knowledge.entry(for: pendingInsightItem, scope: pendingInsightScope)
            pendingInsightLabel = entry?.label ?? ""
            pendingInsightPurpose = entry?.purpose ?? ""
        }
        .onDisappear {
            killFeedbackTask?.cancel()
            portHealthCheckTask?.cancel()
        }
        .animation(panelSwitchAnimation, value: isSettingsExpanded)
        .animation(.easeInOut(duration: 0.2), value: pendingKillItem != nil)
    }

    private var backgroundLayer: some View {
        ZStack {
            LinearGradient(
                colors: isDarkMode
                    ? [
                        Color(red: 0.19, green: 0.23, blue: 0.31).opacity(0.8),
                        Color(red: 0.15, green: 0.2, blue: 0.28).opacity(0.62),
                        Color(red: 0.16, green: 0.22, blue: 0.2).opacity(0.58)
                    ]
                    : [
                        Color(red: 0.995, green: 0.997, blue: 1.0),
                        Color(red: 0.975, green: 0.988, blue: 1.0),
                        Color(red: 0.978, green: 0.994, blue: 0.986)
                    ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay {
                Color.white.opacity(isDarkMode ? 0.04 : 0.26)
            }
        }
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(Color(red: 0.44, green: 0.62, blue: 0.96).opacity(isDarkMode ? 0.2 : 0.2))
                .frame(width: 188, height: 188)
                .blur(radius: 24)
                .offset(x: 36, y: -28)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .bottomLeading) {
            Circle()
                .fill(Color(red: 0.42, green: 0.79, blue: 0.7).opacity(isDarkMode ? 0.16 : 0.18))
                .frame(width: 162, height: 162)
                .blur(radius: 24)
                .offset(x: -34, y: 30)
                .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }

    private var panel: some View {
        VStack(spacing: 9) {
            if let killFeedback {
                killFeedbackBanner(killFeedback)
                    .transition(.opacity)
            }

            heroSection
            Group {
                if isSettingsExpanded {
                    settingsFocusModeSection
                        .transition(
                            .asymmetric(
                                insertion: .opacity,
                                removal: .opacity
                            )
                        )
                } else {
                    regularModeSection
                        .transition(
                            .asymmetric(
                                insertion: .opacity,
                                removal: .opacity
                            )
                        )
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: isDarkMode
                                    ? [
                                        Color.white.opacity(0.1),
                                        Color.white.opacity(0.04)
                                    ]
                                    : [
                                        Color.white.opacity(0.62),
                                        Color.white.opacity(0.28)
                                    ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(panelStrokeColor, lineWidth: 0.9)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(panelInnerStrokeColor, lineWidth: 0.5)
                }
        )
        .shadow(color: Color.black.opacity(isDarkMode ? 0.28 : 0.1), radius: 22, y: 12)
        .shadow(color: Color.white.opacity(isDarkMode ? 0.03 : 0.55), radius: 8, y: -2)
    }

    private var regularModeSection: some View {
        VStack(spacing: 9) {
            metricsBentoSection
            controlsSection
            commandProfilesSection
            listSection
            if !isCompactScreen {
                trendSection
            }
            footerSection
        }
    }

    private var settingsFocusModeSection: some View {
        VStack(spacing: 8) {
            settingsBentoSection

            settingsCollapsibleSection(.overview) {
                metricsBentoSection
            }

            settingsCollapsibleSection(.filters) {
                controlsSection
            }

            settingsCollapsibleSection(.commands) {
                commandProfilesSection
            }

            settingsCollapsibleSection(.ports) {
                listSection
            }

            if !isCompactScreen {
                settingsCollapsibleSection(.trend) {
                    trendSection
                }
            }

            footerSection
        }
    }

    private var compactTrendTile: some View {
        GeometryReader { geometry in
            let points = chartCoordinates(in: geometry.size)
            ZStack {
                if points.count > 1 {
                    chartSmoothAreaPath(points: points, size: geometry.size)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.24, green: 0.55, blue: 0.98).opacity(0.14),
                                    .clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    chartSmoothLinePath(points: points)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.14, green: 0.5, blue: 0.98),
                                    Color(red: 0.34, green: 0.78, blue: 0.88),
                                    Color(red: 0.62, green: 0.48, blue: 0.98)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            style: StrokeStyle(lineWidth: 2.1, lineCap: .round, lineJoin: .round)
                        )
                        .shadow(color: Color(red: 0.25, green: 0.57, blue: 0.98).opacity(0.28), radius: 5, y: 2)

                    if let endPoint = points.last {
                        Circle()
                            .fill(.white.opacity(0.95))
                            .frame(width: 5.2, height: 5.2)
                            .overlay {
                                Circle()
                                    .stroke(Color(red: 0.2, green: 0.54, blue: 0.98), lineWidth: 1.1)
                            }
                            .position(endPoint)
                    }
                }
            }
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 3)
    }

    private func settingsCollapsibleSection<Content: View>(
        _ section: SettingsFocusPanel,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let isExpanded = settingsFocusedExpandedPanel == section
        let isHovered = hoveredSettingsPanel == section
        let iconTint: Color = isExpanded
            ? Color.blue.opacity(0.84)
            : Color.black.opacity(isHovered ? 0.74 : 0.66)
        let titleTint: Color = isExpanded
            ? Color.blue.opacity(0.86)
            : Color.black.opacity(isHovered ? 0.8 : 0.72)
        let metaTint: Color = isExpanded
            ? Color.blue.opacity(0.66)
            : Color.black.opacity(isHovered ? 0.56 : 0.45)

        return VStack(spacing: 6) {
            Button {
                withAnimation(sectionExpandAnimation) {
                    if isExpanded {
                        settingsFocusedExpandedPanel = nil
                    } else {
                        settingsFocusedExpandedPanel = section
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: section.symbol)
                        .font(.system(size: 9.8, weight: .semibold))
                        .foregroundStyle(iconTint)
                        .frame(width: 18, height: 18)
                        .background(
                            Color.white.opacity(isHovered || isExpanded ? 0.72 : 0.56),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                        )

                    Text(section.title(language: settings.appLanguage))
                        .font(.system(size: 9.4, weight: .bold, design: .rounded))
                        .foregroundStyle(titleTint)

                    Spacer(minLength: 4)

                    Text(isExpanded ? tr("收起", "Collapse") : tr("展开", "Expand"))
                        .font(.system(size: 7.7, weight: .semibold))
                        .foregroundStyle(metaTint)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8.6, weight: .bold))
                        .foregroundStyle(metaTint)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(FocusHeaderButtonStyle())
            .onHover { hovering in
                withAnimation(sectionExpandAnimation) {
                    if hovering {
                        hoveredSettingsPanel = section
                    } else if hoveredSettingsPanel == section {
                        hoveredSettingsPanel = nil
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(cardFill(section.tone))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(isHovered || isExpanded ? 0.22 : 0.08),
                                        Color.white.opacity(0.01)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .stroke(
                                Color.white.opacity(isHovered || isExpanded ? (isDarkMode ? 0.36 : 0.86) : (isDarkMode ? 0.22 : 0.7)),
                                lineWidth: isHovered || isExpanded ? 0.9 : 0.65
                            )
                    }
            )
            .shadow(
                color: (isHovered || isExpanded)
                    ? Color.blue.opacity(isDarkMode ? 0.2 : 0.16)
                    : Color.black.opacity(isDarkMode ? 0.1 : 0.04),
                radius: isHovered || isExpanded ? 7 : 4,
                y: isHovered || isExpanded ? 3 : 2
            )
            .animation(sectionExpandAnimation, value: isHovered)
            .animation(sectionExpandAnimation, value: isExpanded)

            if isExpanded {
                content()
                    .transition(
                        .asymmetric(
                            insertion: .opacity,
                            removal: .opacity
                        )
                    )
            }
        }
    }

    private var heroSection: some View {
        bentoCard(.pearl) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("PORTPILOT")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .kerning(1.5)
                        .foregroundStyle(Color.black.opacity(0.45))

                    Text("Pilot your ports")
                        .font(.system(size: 16.8, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.82))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    HStack(spacing: 6) {
                        Circle()
                            .fill(statusTint)
                            .frame(width: 7, height: 7)
                        Text(statusText)
                            .font(.system(size: 10.2, weight: .semibold, design: .rounded))
                            .foregroundStyle(statusTint)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusTint.opacity(0.11), in: Capsule())

                    Text("\(tr("上次扫描", "Last scan")) · \(lastScanText)")
                        .font(.system(size: 9.4, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.52))

                    if isSettingsExpanded {
                        HStack(spacing: 5) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 8, weight: .bold))
                            Text(tr("设置聚焦模式", "Settings Focus Mode"))
                                .font(.system(size: 8.3, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(Color.blue.opacity(0.86))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.blue.opacity(0.12), in: Capsule())
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                }

                Spacer(minLength: 8)

                VStack(spacing: 8) {
                    if isCompactScreen {
                        HStack(alignment: .center, spacing: 6) {
                            PortGauge(value: totalUniquePortCount)
                                .frame(width: headerGaugeSize.width, height: headerGaugeSize.height)
                            compactTrendTile
                                .frame(width: headerGaugeSize.width, height: headerGaugeSize.height)
                            circleControlButton(
                                systemName: isSettingsExpanded ? "xmark" : "slider.horizontal.3"
                            ) {
                                toggleSettingsFocus()
                            }
                        }
                    } else {
                        circleControlButton(
                            systemName: isSettingsExpanded ? "xmark" : "slider.horizontal.3"
                        ) {
                            toggleSettingsFocus()
                        }

                        PortGauge(value: totalUniquePortCount)
                            .frame(width: headerGaugeSize.width, height: headerGaugeSize.height)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(minHeight: heroContentMinHeight, alignment: .center)
        }
    }

    private var metricsBentoSection: some View {
        HStack(alignment: .top, spacing: 8) {
            bentoCard(.sky) {
                VStack(alignment: .leading, spacing: 0) {
                    metricTitle(tr("检测实例 / 占用端口", "Listeners / Occupied Ports"))
                    Text("\(filteredListeners.count) / \(currentOccupiedPortCount)")
                        .font(.system(size: 23, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.black.opacity(0.82))
                        .lineLimit(1)
                        .minimumScaleFactor(0.74)
                        .padding(.top, 1)
                    Spacer(minLength: 0)
                    Text(isFiltering ? tr("筛选视图", "Filtered View") : tr("全局视图", "Global View"))
                        .font(.system(size: 9.1, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(height: metricsCardContentHeight, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            bentoCard(.peach) {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 2) {
                        metricTitle(tr("刷新频率", "Refresh"))
                        Text(settings.refreshInterval.label(language: settings.appLanguage))
                            .font(.system(size: 12.8, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.black.opacity(0.8))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer(minLength: 4)
                    Divider().opacity(0.16)
                    Spacer(minLength: 4)

                    VStack(alignment: .leading, spacing: 2) {
                        metricTitle(tr("计数方式", "Count Mode"))
                        Text(modeText)
                            .font(.system(size: 12.8, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.black.opacity(0.8))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: metricsCardContentHeight, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var controlsSection: some View {
        bentoCard(.pearl) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)

                    TextField(tr("搜索端口 / 进程 / PID", "Search port / process / PID"), text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule().stroke(Color.white.opacity(isDarkMode ? 0.2 : 0.72), lineWidth: 0.75)
                }

                Menu {
                    ForEach(SortMode.allCases) { mode in
                        Button {
                            sortMode = mode
                        } label: {
                            if mode == sortMode {
                                Label(mode.label(language: settings.appLanguage), systemImage: "checkmark")
                            } else {
                                Text(mode.label(language: settings.appLanguage))
                            }
                        }
                    }
                } label: {
                    Text(sortMode.label(language: settings.appLanguage))
                        .font(.system(size: 10.4, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.74))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay {
                            Capsule().stroke(Color.white.opacity(isDarkMode ? 0.2 : 0.72), lineWidth: 0.75)
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var commandProfilesSection: some View {
        bentoCard(.peach) {
            HStack {
                Text(tr("启动命令", "Startup Commands"))
                    .font(.system(size: 10.6, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.82))

                Menu {
                    Button {
                        selectedWorkspaceID = Self.allWorkspaceToken
                    } label: {
                        if selectedWorkspaceID == Self.allWorkspaceToken {
                            Label(tr("全部场景", "All Workspaces"), systemImage: "checkmark")
                        } else {
                            Text(tr("全部场景", "All Workspaces"))
                        }
                    }

                    if !commands.workspaceNames.isEmpty {
                        Divider()
                    }

                    ForEach(commands.workspaceNames, id: \.self) { workspace in
                        Button {
                            selectedWorkspaceID = workspace
                        } label: {
                            if selectedWorkspaceID == workspace {
                                Label(workspace, systemImage: "checkmark")
                            } else {
                                Text(workspace)
                            }
                        }
                    }
                } label: {
                    Text(selectedWorkspaceTitle)
                        .font(.system(size: 8.7, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.66))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.46), in: Capsule())
                }
                .buttonStyle(.plain)

                Spacer()

                if !scopedProfiles.isEmpty {
                    Button(tr("启动", "Start")) {
                        startInactiveProfilesInSelectedWorkspace()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 8.8, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.65))
                    .disabled(scopedStartableCount == 0)
                }

                if scopedRunningCount > 0 {
                    Button(tr("停止", "Stop")) {
                        commands.stopWorkspace(named: selectedWorkspaceName)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 8.8, weight: .semibold))
                    .foregroundStyle(.red.opacity(0.75))
                }

                if !scopedProfiles.isEmpty {
                    Button(tr("重启", "Restart")) {
                        commands.restartWorkspace(named: selectedWorkspaceName)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 8.8, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.65))
                }

                Button(tr("编辑 YAML", "Edit YAML")) {
                    commands.openProfilesFile()
                }
                .buttonStyle(.plain)
                .font(.system(size: 8.8, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.65))

                Button(tr("重载", "Reload")) {
                    commands.reloadProfiles()
                }
                .buttonStyle(.plain)
                .font(.system(size: 8.8, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.65))
            }
            .padding(.bottom, 6)

            if !conflictFixSuggestions.isEmpty {
                conflictFixSection
                    .padding(.bottom, 6)
            } else if !unmanagedConflictPorts.isEmpty {
                Text(
                    tr(
                        "发现端口冲突：\(unmanagedConflictPorts.map(plainNumber).joined(separator: ", "))（非托管命令，需手动处理）",
                        "Port conflicts detected: \(unmanagedConflictPorts.map(plainNumber).joined(separator: ", ")) (unmanaged commands, manual handling required)"
                    )
                )
                    .font(.system(size: 8.4, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 6)
                    .lineLimit(2)
            }

            if scopedProfiles.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text(
                        selectedWorkspaceName == nil
                            ? tr("暂无命令配置。点击「编辑 YAML」创建常用启动命令。", "No startup profiles. Click \"Edit YAML\" to add your common commands.")
                            : tr("当前场景没有命令。可在 YAML 的 tags 里加 workspace:名称。", "No commands in this workspace. Add tags like workspace:your-name in YAML.")
                    )
                        .font(.system(size: 9.2, weight: .medium))
                        .foregroundStyle(.secondary)

                    Text(tr("格式示例：name / cwd / command / ports / tags", "Format: name / cwd / command / ports / tags"))
                        .font(.system(size: 8.4, weight: .medium))
                        .foregroundStyle(.secondary.opacity(0.85))
                }
            } else {
                Group {
                    if scopedProfiles.count > 3 {
                        ScrollView {
                            VStack(spacing: 0) {
                                ForEach(Array(scopedProfiles.enumerated()), id: \.element.id) { index, profile in
                                    commandProfileRow(profile)
                                    if index < scopedProfiles.count - 1 {
                                        Divider().opacity(0.12)
                                    }
                                }
                            }
                        }
                        .unifiedScrollVisual(isDarkMode: isDarkMode)
                        .frame(maxHeight: commandProfilesListMaxHeight)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(scopedProfiles.enumerated()), id: \.element.id) { index, profile in
                                commandProfileRow(profile)
                                if index < scopedProfiles.count - 1 {
                                    Divider().opacity(0.12)
                                }
                            }
                        }
                    }
                }
            }

            if let error = commands.lastErrorMessage, !error.isEmpty {
                Text(error)
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(.red.opacity(0.8))
                    .lineLimit(2)
                    .padding(.top, 6)
            }
        }
    }

    private func commandProfileRow(_ profile: CommandProfile) -> some View {
        let runningInfo = commands.runningByProfileID[profile.id]
        let externalRunningPID = detectedExternalRunningPIDByProfileID[profile.id]
        let isExternallyRunning = runningInfo == nil && externalRunningPID != nil

        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1.5) {
                HStack(spacing: 5) {
                    Text(profile.name)
                        .font(.system(size: 9.9, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.78))
                        .lineLimit(1)

                    if let workspace = commands.workspaceName(for: profile) {
                        Text(workspace)
                            .font(.system(size: 7.4, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.blue.opacity(0.82))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.blue.opacity(0.12), in: Capsule())
                    }
                }

                if let note = profile.note, !note.isEmpty {
                    Text(note)
                        .font(.system(size: 8.2, weight: .semibold))
                        .foregroundStyle(Color.blue.opacity(0.78))
                        .lineLimit(2)
                }

                Text(profile.command)
                    .font(.system(size: 8.4, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(profile.cwd)
                    .font(.system(size: 8.1, weight: .medium))
                    .foregroundStyle(.secondary.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let inferredPort = commands.inferredPort(for: profile) {
                    Text("\(tr("端口", "Port")) \(plainNumber(inferredPort))")
                        .font(.system(size: 8.1, weight: .semibold))
                        .foregroundStyle(Color.blue.opacity(0.82))
                }

                if let runningInfo {
                    Text("\(tr("运行中", "Running")) · PID \(plainNumber(Int(runningInfo.pid)))")
                        .font(.system(size: 8.1, weight: .semibold))
                        .foregroundStyle(Color.green.opacity(0.82))
                } else if let externalRunningPID {
                    Text("\(tr("运行中（外部）", "Running (External)")) · PID \(plainNumber(externalRunningPID))")
                        .font(.system(size: 8.1, weight: .semibold))
                        .foregroundStyle(Color.green.opacity(0.82))
                }
            }

            Spacer(minLength: 0)

            if commands.isStopping(profile) {
                ProgressView()
                    .controlSize(.small)
            } else if runningInfo != nil {
                Button(tr("停止", "Stop")) {
                    Task {
                        await commands.stop(profile: profile)
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 8.7, weight: .semibold))
                .foregroundStyle(.red.opacity(0.8))

                Button(tr("重启", "Restart")) {
                    commands.restart(profile: profile)
                }
                .buttonStyle(.plain)
                .font(.system(size: 8.7, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.65))

                Button(tr("改端口", "Change Port")) {
                    requestPortEdit(for: profile)
                }
                .buttonStyle(.plain)
                .font(.system(size: 8.7, weight: .semibold))
                .foregroundStyle(Color.orange.opacity(0.85))
            } else if isExternallyRunning {
                Text(tr("已在运行", "Already Running"))
                    .font(.system(size: 8.2, weight: .semibold))
                    .foregroundStyle(Color.green.opacity(0.82))

                Button(tr("改端口", "Change Port")) {
                    requestPortEdit(for: profile)
                }
                .buttonStyle(.plain)
                .font(.system(size: 8.7, weight: .semibold))
                .foregroundStyle(Color.orange.opacity(0.85))
            } else {
                Button(tr("启动", "Start")) {
                    commands.start(profile: profile)
                }
                .buttonStyle(.plain)
                .font(.system(size: 8.7, weight: .semibold))
                .foregroundStyle(Color.blue.opacity(0.82))

                Button(tr("改端口", "Change Port")) {
                    requestPortEdit(for: profile)
                }
                .buttonStyle(.plain)
                .font(.system(size: 8.7, weight: .semibold))
                .foregroundStyle(Color.orange.opacity(0.85))
            }
        }
        .padding(.vertical, 6)
    }

    private func normalizeCommandForMatch(_ command: String) -> String {
        command
            .replacingOccurrences(
                of: "\\s+",
                with: " ",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func isProfileActive(_ profile: CommandProfile) -> Bool {
        commands.runningByProfileID[profile.id] != nil || detectedExternalRunningPIDByProfileID[profile.id] != nil
    }

    private func startInactiveProfilesInSelectedWorkspace() {
        let targets = scopedProfiles.filter { profile in
            !isProfileActive(profile)
        }
        for profile in targets {
            commands.start(profile: profile)
        }
    }

    private var conflictFixSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(tr("冲突修复建议", "Conflict Fix Suggestions"))
                .font(.system(size: 8.7, weight: .bold, design: .rounded))
                .foregroundStyle(Color.orange.opacity(0.9))

            ForEach(conflictFixSuggestions) { suggestion in
                HStack(spacing: 6) {
                    Text("\(suggestion.profile.name)：\(plainNumber(suggestion.conflictPort)) → \(plainNumber(suggestion.suggestedPort))")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.74))
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    Button(tr("一键修复", "One-Click Fix")) {
                        requestConflictFixConfirmation(suggestion)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 8.1, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.92), in: Capsule())
                }

                Text(
                    tr(
                        "冲突端口 \(plainNumber(suggestion.conflictPort)) 共有 \(plainNumber(suggestion.participantCount)) 个进程监听",
                        "Port \(plainNumber(suggestion.conflictPort)) has \(plainNumber(suggestion.participantCount)) listening processes"
                    )
                )
                    .font(.system(size: 7.9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.orange.opacity(0.26), lineWidth: 0.7)
        }
    }

    private var settingsBentoSection: some View {
        VStack(spacing: 10) {
            settingSectionCard(
                title: tr("扫描与健康检查", "Scan & Health Check"),
                subtitle: tr("Port 变更后自动验证是否生效", "Auto-verify after port changes"),
                symbol: "waveform.path.ecg",
                tone: .sky
            ) {
                settingOptionGridRow(
                    title: tr("语言", "Language"),
                    subtitle: tr("全局界面文案", "Global UI language"),
                    choices: [
                        SettingChoice(id: "lang-cn", title: tr("中文", "Chinese"), value: AppLanguage.chinese),
                        SettingChoice(id: "lang-en", title: "English", value: AppLanguage.english)
                    ],
                    selection: $settings.appLanguage
                )

                settingOptionGridRow(
                    title: tr("刷新频率", "Refresh"),
                    subtitle: tr("后台扫描周期", "Background scan interval"),
                    choices: RefreshIntervalOption.allCases.map { option in
                        SettingChoice(
                            id: "refresh-\(option.rawValue)",
                            title: option.label(language: settings.appLanguage),
                            value: option
                        )
                    },
                    selection: $settings.refreshInterval
                )

                settingOptionGridRow(
                    title: tr("计数方式", "Count Mode"),
                    subtitle: tr("菜单栏 : N 统计口径", "Menu-bar : N counting rule"),
                    choices: [
                        SettingChoice(id: "count-inst", title: tr("实例", "Instance"), value: PortCountMode.portAndPID),
                        SettingChoice(id: "count-port", title: tr("端口", "Port"), value: PortCountMode.portOnly)
                    ],
                    selection: $settings.countMode
                )

                settingOptionGridRow(
                    title: tr("健康重试", "Health Retries"),
                    subtitle: tr("改端口后最多检测次数", "Max retries after port change"),
                    choices: HealthCheckAttemptsOption.allCases.map { option in
                        SettingChoice(
                            id: "retries-\(option.rawValue)",
                            title: option.label(language: settings.appLanguage),
                            value: option
                        )
                    },
                    selection: $settings.healthCheckMaxAttempts
                )

                settingOptionGridRow(
                    title: tr("检测间隔", "Probe Interval"),
                    subtitle: tr("每次健康检查的等待时间", "Wait between health probes"),
                    choices: HealthCheckIntervalOption.allCases.map { option in
                        SettingChoice(
                            id: "probe-\(option.rawValue)",
                            title: option.label(language: settings.appLanguage),
                            value: option
                        )
                    },
                    selection: $settings.healthCheckProbeInterval
                )
            }

            settingSectionCard(
                title: tr("安全与通知", "Safety & Notifications"),
                subtitle: tr("高风险操作和系统提醒", "Risky actions and system alerts"),
                symbol: "shield.lefthalf.filled.badge.checkmark",
                tone: .mint
            ) {
                settingToggleRow(
                    title: tr("开机启动", "Launch at Login"),
                    subtitle: tr("登录系统后自动启动 PortPilot", "Start PortPilot automatically after login"),
                    isOn: $settings.launchAtLogin
                )
                settingToggleRow(
                    title: tr("允许结束进程", "Enable Kill"),
                    subtitle: tr("关闭后隐藏 Kill 操作", "Hide kill action when disabled"),
                    isOn: $settings.enableKill
                )
                settingToggleRow(
                    title: tr("通知：新端口", "Notify: New Ports"),
                    subtitle: tr("检测到新监听端口时提醒", "Alert when new listening ports are detected"),
                    isOn: $settings.notifyOnNewPort
                )
                settingToggleRow(
                    title: tr("通知：端口冲突", "Notify: Port Conflict"),
                    subtitle: tr("同端口出现多个 PID 时提醒", "Alert when one port has multiple PIDs"),
                    isOn: $settings.notifyOnPortConflict
                )
                settingToggleRow(
                    title: tr("通知：扫描异常", "Notify: Scan Failure"),
                    subtitle: tr("连续失败 3 次后提醒", "Alert after 3 consecutive scan failures"),
                    isOn: $settings.notifyOnScannerFailure
                )

                if let launchError = settings.launchAtLoginError, !launchError.isEmpty {
                    Text(launchError)
                        .font(.system(size: 7.8, weight: .semibold))
                        .foregroundStyle(.red.opacity(0.84))
                        .padding(.horizontal, 2)
                }
            }

            settingSectionCard(
                title: tr("显示与规则", "Display & Rules"),
                subtitle: tr("提升可读性与自动化体验", "Improve readability and automation"),
                symbol: "slider.horizontal.3",
                tone: .pearl
            ) {
                settingToggleRow(
                    title: tr("显示命令行", "Show Command Line"),
                    subtitle: tr("用于区分多个同名进程（可能含敏感参数）", "Differentiate same-name processes (may contain sensitive args)"),
                    isOn: $settings.showCommandLine
                )
                settingToggleRow(
                    title: tr("显示资源徽标", "Show Resource Badges"),
                    subtitle: tr("在进程名旁展示 CPU / 内存占用", "Show CPU / memory badges beside process names"),
                    isOn: $settings.showResourceBadges
                )
                settingToggleRow(
                    title: tr("自动建议启动项", "Auto Suggest Startup Profiles"),
                    subtitle: tr("发现常见开发服务时提示保存", "Suggest saving common dev services"),
                    isOn: $settings.autoSuggestProfiles
                )

                settingTextRow(
                    title: tr("忽略端口", "Ignored Ports"),
                    subtitle: tr("逗号分隔，例如 3000, 8080", "Comma-separated, e.g. 3000, 8080"),
                    placeholder: "3000, 8080",
                    text: $settings.ignoredPortsText
                )
                settingTextRow(
                    title: tr("忽略进程", "Ignored Processes"),
                    subtitle: tr("逗号分隔，例如 ssh, node", "Comma-separated, e.g. ssh, node"),
                    placeholder: "ssh, node",
                    text: $settings.ignoredProcessesText
                )
                settingTextRow(
                    title: tr("进程别名", "Process Aliases"),
                    subtitle: tr("例如 node=商城后端, ssh=开发隧道", "e.g. node=Store API, ssh=Dev Tunnel"),
                    placeholder: tr("node=前端服务, ssh=隧道", "node=Frontend, ssh=Tunnel"),
                    text: $settings.processAliasesText
                )

                Text(
                    tr(
                        "可在列表右键「编辑可读说明」添加用途解释；数据仅保存在本机。",
                        "Use context menu \"Edit friendly note\" in the list to add purpose hints; data stays local."
                    )
                )
                .font(.system(size: 7.8, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.52))
                .padding(.top, 2)
            }
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func settingSectionCard<Content: View>(
        title: String,
        subtitle: String,
        symbol: String,
        tone: BentoTone,
        @ViewBuilder content: () -> Content
    ) -> some View {
        bentoCard(tone) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 11.2, weight: .semibold))
                    .foregroundStyle(Color.blue.opacity(0.84))
                    .frame(width: 24, height: 24)
                    .background(Color.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.65), lineWidth: 0.6)
                    }

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 10.1, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.78))
                        .lineLimit(1)
                        .minimumScaleFactor(0.84)

                    Text(subtitle)
                        .font(.system(size: 7.8, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.46))
                        .lineLimit(1)
                        .minimumScaleFactor(0.84)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.28), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(Color.white.opacity(0.6), lineWidth: 0.55)
            }

            VStack(spacing: 8) {
                content()
            }
            .padding(.top, 8)
        }
    }

    private func settingOptionGridRow<Value: Hashable>(
        title: String,
        subtitle: String,
        choices: [SettingChoice<Value>],
        selection: Binding<Value>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 8.9, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.76))
                .lineLimit(1)
            Text(subtitle)
                .font(.system(size: 7.4, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.47))
                .lineLimit(1)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 64), spacing: 6, alignment: .leading)],
                alignment: .leading,
                spacing: 6
            ) {
                ForEach(choices) { choice in
                    Button {
                        selection.wrappedValue = choice.value
                    } label: {
                        HStack(spacing: 4) {
                            Text(choice.title)
                                .font(.system(size: 8.3, weight: .semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            if selection.wrappedValue == choice.value {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 6.8, weight: .bold))
                            }
                        }
                        .foregroundStyle(
                            selection.wrappedValue == choice.value
                                ? Color.blue.opacity(0.9)
                                : Color.black.opacity(0.68)
                        )
                        .frame(maxWidth: .infinity, minHeight: 24)
                        .padding(.horizontal, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(
                                    selection.wrappedValue == choice.value
                                        ? Color.blue.opacity(0.16)
                                        : Color.white.opacity(0.68)
                                )
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(
                                    selection.wrappedValue == choice.value
                                        ? Color.blue.opacity(0.4)
                                        : Color.white.opacity(0.66),
                                    lineWidth: 0.62
                                )
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.36), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.58), lineWidth: 0.6)
        }
    }

    private func settingPickerRow<Content: View>(
        title: String,
        subtitle: String,
        contentWidth: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 8.8, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.74))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Text(subtitle)
                    .font(.system(size: 7.4, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.46))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(minWidth: 88, alignment: .leading)
            .layoutPriority(1)
            Spacer(minLength: 8)
            content()
                .frame(width: contentWidth)
                .font(.system(size: 8.3, weight: .semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.52), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.34), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.55), lineWidth: 0.55)
        }
    }

    private func settingStackedPickerRow<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 8.8, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.74))
                .lineLimit(1)
                .minimumScaleFactor(0.84)
            Text(subtitle)
                .font(.system(size: 7.4, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.46))
                .lineLimit(1)
                .minimumScaleFactor(0.84)

            content()
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.52), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.34), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.55), lineWidth: 0.55)
        }
    }

    private func settingToggleRow(
        title: String,
        subtitle: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 8.9, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.76))
                Text(subtitle)
                    .font(.system(size: 7.4, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.5))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.6), in: Capsule())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.36), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.58), lineWidth: 0.6)
        }
    }

    private func settingTextRow(
        title: String,
        subtitle: String,
        placeholder: String,
        text: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 8.9, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.76))
                .lineLimit(1)
            Text(subtitle)
                .font(.system(size: 7.3, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.5))
                .lineLimit(1)

            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 8.6, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.66), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.white.opacity(0.58), lineWidth: 0.6)
                }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.36), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.58), lineWidth: 0.6)
        }
    }

    private var listSection: some View {
        bentoCard(.pearl) {
            HStack {
                Text(tr("端口列表", "Ports"))
                    .font(.system(size: 12.2, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.82))
                Spacer()
                Text(countLabel)
                    .font(.system(size: 9.2, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 6)

            if filteredListeners.isEmpty {
                VStack(spacing: 4) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(tr("暂无监听进程", "No listeners"))
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.74))
                }
                .frame(maxWidth: .infinity, minHeight: listHeight)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(filteredListeners.enumerated()), id: \.element.id) { index, item in
                            portRow(item)
                            if index < filteredListeners.count - 1 {
                                Divider().opacity(0.12)
                            }
                        }
                    }
                }
                .unifiedScrollVisual(isDarkMode: isDarkMode)
                .frame(height: listHeight)
            }
        }
    }

    private var trendSection: some View {
        bentoCard(.sky) {
            HStack {
                Text(tr("趋势", "Trend"))
                    .font(.system(size: 9.7, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.82))
                Spacer()
                Text(tr("全局端口数", "Global Port Count"))
                    .font(.system(size: 7.6, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 2)

            GeometryReader { geometry in
                let points = chartCoordinates(in: geometry.size)

                ZStack {
                    chartGrid(size: geometry.size)

                    chartSmoothAreaPath(points: points, size: geometry.size)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.25, green: 0.57, blue: 0.98).opacity(0.26),
                                    .clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    chartSmoothLinePath(points: points)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.14, green: 0.5, blue: 0.98),
                                    Color(red: 0.34, green: 0.78, blue: 0.88),
                                    Color(red: 0.59, green: 0.48, blue: 0.98)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            style: StrokeStyle(lineWidth: 2.9, lineCap: .round, lineJoin: .round)
                        )
                        .shadow(color: Color(red: 0.2, green: 0.52, blue: 0.96).opacity(0.34), radius: 8, y: 4)

                    if let endPoint = points.last {
                        Circle()
                            .fill(.white)
                            .frame(width: 10, height: 10)
                            .overlay {
                                Circle().stroke(Color.blue, lineWidth: 2)
                            }
                            .position(endPoint)
                    }
                }
            }
            .frame(height: 58)

            HStack {
                Text(axisLabel(for: history.first?.time))
                Spacer()
                Text(axisLabel(for: history.last?.time))
            }
            .font(.system(size: 8, weight: .medium))
            .foregroundStyle(.secondary)
        }
    }

    private var footerSection: some View {
        HStack(spacing: 8) {
            Label(
                commands.runningByProfileID.isEmpty
                    ? (settings.enableKill ? tr("Kill 已开启", "Kill Enabled") : tr("Kill 已关闭", "Kill Disabled"))
                    : tr("已运行 \(plainNumber(commands.runningByProfileID.count)) 个命令", "\(plainNumber(commands.runningByProfileID.count)) commands running"),
                systemImage: commands.runningByProfileID.isEmpty
                    ? (settings.enableKill ? "bolt.trianglebadge.exclamationmark.fill" : "bolt.slash")
                    : "play.circle.fill"
            )
            .font(.system(size: 9.4, weight: .semibold))
            .foregroundStyle(
                commands.runningByProfileID.isEmpty
                    ? (settings.enableKill ? Color(red: 0.18, green: 0.63, blue: 0.42) : .secondary)
                    : Color.blue.opacity(0.82)
            )

            Spacer()

            circleControlButton(systemName: isSettingsExpanded ? "slider.horizontal.3" : "gearshape") {
                toggleSettingsFocus()
            }

            circleControlButton(systemName: "arrow.clockwise") {
                Task { await scanner.rescanNow() }
            }
            .disabled(scanner.isScanning)

            circleControlButton(systemName: "square.and.arrow.up") {
                exportSnapshot()
            }

            circleControlButton(systemName: "power") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 1)
    }

    private func bentoCard<Content: View>(
        _ tone: BentoTone,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(cardFill(tone))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(isDarkMode ? 0.2 : 0.74), lineWidth: 0.75)
                }
        )
        .shadow(color: Color.black.opacity(isDarkMode ? 0.12 : 0.04), radius: 8, y: 4)
    }

    private func killConfirmOverlay(for item: PortsStore.ListenerItem) -> some View {
        ZStack {
            Color.black.opacity(0.2)
                .ignoresSafeArea()
                .onTapGesture {
                    pendingKillItem = nil
                }

            VStack(alignment: .leading, spacing: 10) {
                Text(tr("结束这个进程？", "Terminate this process?"))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.84))

                Text("\(presentedProcessName(for: item)) · PID \(plainNumber(item.pid)) · \(tr("端口", "Port")) \(plainNumber(item.port))")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if item.displayName != item.processName {
                    Text("\(tr("原始进程", "Raw Process")): \(item.processName)")
                        .font(.system(size: 8.4, weight: .medium))
                        .foregroundStyle(.secondary.opacity(0.8))
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    Button(tr("取消", "Cancel")) {
                        pendingKillItem = nil
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.2, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.68))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.72), in: Capsule())

                    Spacer(minLength: 0)

                    Button(tr("结束进程", "Terminate")) {
                        performKill(for: item)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.2, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(Color.red.opacity(0.9), in: Capsule())
                    .disabled(killInFlightPID != nil)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(width: 314)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.8), lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(0.2), radius: 18, y: 8)
        }
    }

    private func insightEditorOverlay(for item: PortsStore.ListenerItem) -> some View {
        ZStack {
            Color.black.opacity(0.16)
                .ignoresSafeArea()
                .onTapGesture {
                    pendingInsightItem = nil
                }

            VStack(alignment: .leading, spacing: 10) {
                Text(tr("编辑可读说明", "Edit Friendly Note"))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.84))

                Text("\(presentedProcessName(for: item)) · \(tr("端口", "Port")) \(plainNumber(item.port))")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(tr("作用范围", "Scope"))
                        .font(.system(size: 9.3, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.7))

                    Picker("", selection: $pendingInsightScope) {
                        ForEach(PortKnowledgeStore.MatchScope.allCases) { scope in
                            Text(scope.label(language: settings.appLanguage)).tag(scope)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.mini)
                    .frame(width: 128)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(tr("名称（可选）", "Name (Optional)"))
                        .font(.system(size: 8.8, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.62))
                    TextField(
                        tr("例如：商城后端 API", "e.g. Store Backend API"),
                        text: $pendingInsightLabel
                    )
                    .textFieldStyle(.plain)
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(isDarkMode ? 0.2 : 0.68), lineWidth: 0.75)
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(tr("用途说明（可选）", "Purpose (Optional)"))
                        .font(.system(size: 8.8, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.62))
                    TextField(
                        tr("例如：用于本地支付回调调试", "e.g. Local payment callback debugging"),
                        text: $pendingInsightPurpose,
                        axis: .vertical
                    )
                    .textFieldStyle(.plain)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(2...3)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(isDarkMode ? 0.2 : 0.68), lineWidth: 0.75)
                    }
                }

                HStack(spacing: 8) {
                    Button(tr("取消", "Cancel")) {
                        pendingInsightItem = nil
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.8, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.66))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.72), in: Capsule())

                    Button(tr("清空", "Clear")) {
                        knowledge.remove(scope: pendingInsightScope, for: item)
                        pendingInsightItem = nil
                        showKillFeedback(tr("已清空该范围说明", "Cleared note for selected scope"), isError: false)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.8, weight: .semibold))
                    .foregroundStyle(Color.orange.opacity(0.86))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.orange.opacity(0.12), in: Capsule())

                    Spacer(minLength: 0)

                    Button(tr("保存", "Save")) {
                        knowledge.save(
                            label: pendingInsightLabel,
                            purpose: pendingInsightPurpose,
                            scope: pendingInsightScope,
                            for: item
                        )
                        pendingInsightItem = nil
                        showKillFeedback(tr("已保存可读说明", "Friendly note saved"), isError: false)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.8, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.9), in: Capsule())
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(width: 342)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.82), lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(0.16), radius: 15, y: 8)
        }
    }

    private func killFeedbackBanner(_ feedback: KillFeedback) -> some View {
        let accent = feedback.isError ? Color.red.opacity(0.88) : Color.green.opacity(0.84)
        let tintBackground = feedback.isError
            ? Color.red.opacity(0.08)
            : Color.green.opacity(0.08)

        return HStack(spacing: 7) {
            Text(feedback.isError ? tr("操作失败", "Failed") : tr("操作完成", "Done"))
                .font(.system(size: 10.2, weight: .bold, design: .rounded))
                .foregroundStyle(accent)

            Text(feedback.message)
                .font(.system(size: 9.3, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.75))
                .lineLimit(2)

            Spacer(minLength: 0)

            Button {
                withAnimation(feedbackBannerAnimation) {
                    killFeedback = nil
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8.2, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.45))
                    .frame(width: 18, height: 18)
                    .background(Color.white.opacity(0.42), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(tintBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(accent.opacity(0.35), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
        .zIndex(20)
    }

    private func autoProfileSuggestionOverlay(_ suggestion: AutoProfileSuggestion) -> some View {
        ZStack {
            Color.black.opacity(0.12)
                .ignoresSafeArea()
                .onTapGesture {
                    dismissAutoSuggestion(for: suggestion)
                }

            VStack(alignment: .leading, spacing: 10) {
                Text(tr("发现可保存的启动命令", "Detected savable startup command"))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.84))

                Text("\(presentedProcessName(for: suggestion.item)) · PID \(plainNumber(suggestion.item.pid)) · \(tr("端口", "Port")) \(plainNumber(suggestion.item.port))")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if let commandLine = suggestion.item.commandLine, !commandLine.isEmpty {
                    Text(commandLine)
                        .font(.system(size: 8.5, design: .monospaced))
                        .foregroundStyle(.secondary.opacity(0.9))
                        .lineLimit(2)
                        .truncationMode(.middle)
                }

                HStack(spacing: 8) {
                    Button(tr("忽略", "Ignore")) {
                        dismissAutoSuggestion(for: suggestion)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.7, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.66))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.72), in: Capsule())

                    Spacer(minLength: 0)

                    Button(tr("保存为启动项", "Save as Startup")) {
                        acceptAutoSuggestion(suggestion)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.7, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.88), in: Capsule())
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(width: 332)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.82), lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(0.16), radius: 15, y: 8)
        }
    }

    private func portEditOverlay(for profile: CommandProfile) -> some View {
        ZStack {
            Color.black.opacity(0.16)
                .ignoresSafeArea()
                .onTapGesture {
                    guard !portEditInFlight else { return }
                    pendingPortEditProfile = nil
                }

            VStack(alignment: .leading, spacing: 10) {
                Text(tr("修改启动端口", "Change Startup Port"))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.84))

                Text(profile.name)
                    .font(.system(size: 10.4, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(tr("新端口", "New Port"))
                        .font(.system(size: 9.6, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.72))
                    TextField(tr("例如 3001", "e.g. 3001"), text: $pendingPortEditValue)
                        .textFieldStyle(.plain)
                        .font(.system(size: 10.4, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.white.opacity(isDarkMode ? 0.18 : 0.66), lineWidth: 0.75)
                        }
                }

                Toggle(tr("若正在运行，修改后自动重启", "If running, auto-restart after change"), isOn: $pendingPortEditRestart)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .font(.system(size: 9.1, weight: .medium))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Button(tr("取消", "Cancel")) {
                        guard !portEditInFlight else { return }
                        pendingPortEditProfile = nil
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.8, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.66))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.72), in: Capsule())

                    Spacer(minLength: 0)

                    Button {
                        applyPortEdit(for: profile)
                    } label: {
                        if portEditInFlight {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 44)
                        } else {
                            Text(tr("保存", "Save"))
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.8, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.9), in: Capsule())
                    .disabled(portEditInFlight)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(width: 320)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.82), lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(0.16), radius: 15, y: 8)
        }
    }

    private func conflictFixConfirmOverlay(for suggestion: ConflictFixSuggestion) -> some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .onTapGesture {
                    guard !portEditInFlight else { return }
                    pendingConflictFixSuggestion = nil
                }

            VStack(alignment: .leading, spacing: 10) {
                Text(tr("确认一键修复冲突？", "Confirm one-click conflict fix?"))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.84))

                Text(
                    tr(
                        "\(suggestion.profile.name) 将从端口 \(plainNumber(suggestion.conflictPort)) 改到 \(plainNumber(suggestion.suggestedPort))",
                        "\(suggestion.profile.name) will change port \(plainNumber(suggestion.conflictPort)) to \(plainNumber(suggestion.suggestedPort))"
                    )
                )
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Text(tr("若该命令正在运行，将自动重启以生效。", "If running, it will auto-restart to apply changes."))
                    .font(.system(size: 8.7, weight: .medium))
                    .foregroundStyle(.secondary.opacity(0.92))

                HStack(spacing: 8) {
                    Button(tr("取消", "Cancel")) {
                        guard !portEditInFlight else { return }
                        pendingConflictFixSuggestion = nil
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.8, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.66))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.72), in: Capsule())

                    Spacer(minLength: 0)

                    Button {
                        applyConflictSuggestion(suggestion)
                    } label: {
                        if portEditInFlight {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 44)
                        } else {
                            Text(tr("确认修复", "Confirm Fix"))
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.8, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.orange.opacity(0.92), in: Capsule())
                    .disabled(portEditInFlight)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(width: 334)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.82), lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(0.18), radius: 15, y: 8)
        }
    }

    private func cardFill(_ tone: BentoTone) -> LinearGradient {
        switch tone {
        case .pearl:
            return LinearGradient(
                colors: isDarkMode
                    ? [
                        Color.white.opacity(0.11),
                        Color.white.opacity(0.05)
                    ]
                    : [
                        Color.white.opacity(0.72),
                        Color.white.opacity(0.34)
                    ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .sky:
            return LinearGradient(
                colors: isDarkMode
                    ? [
                        Color(red: 0.3, green: 0.45, blue: 0.7).opacity(0.26),
                        Color(red: 0.24, green: 0.37, blue: 0.56).opacity(0.16)
                    ]
                    : [
                        Color(red: 0.86, green: 0.93, blue: 1.0).opacity(0.52),
                        Color(red: 0.92, green: 0.96, blue: 1.0).opacity(0.28)
                    ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .mint:
            return LinearGradient(
                colors: isDarkMode
                    ? [
                        Color(red: 0.36, green: 0.62, blue: 0.53).opacity(0.24),
                        Color(red: 0.26, green: 0.5, blue: 0.45).opacity(0.14)
                    ]
                    : [
                        Color(red: 0.86, green: 0.97, blue: 0.93).opacity(0.5),
                        Color(red: 0.93, green: 0.98, blue: 0.96).opacity(0.26)
                    ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .peach:
            return LinearGradient(
                colors: isDarkMode
                    ? [
                        Color(red: 0.66, green: 0.5, blue: 0.36).opacity(0.24),
                        Color(red: 0.54, green: 0.4, blue: 0.31).opacity(0.14)
                    ]
                    : [
                        Color(red: 1.0, green: 0.93, blue: 0.86).opacity(0.48),
                        Color(red: 1.0, green: 0.96, blue: 0.92).opacity(0.24)
                    ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private func circleControlButton(
        systemName: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10.6, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(isDarkMode ? 0.9 : 0.72))
                .frame(width: 24, height: 24)
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(isDarkMode ? 0.24 : 0.78), lineWidth: 0.8)
                }
        }
        .buttonStyle(.plain)
    }

    private func metricTitle(_ value: String) -> some View {
        Text(value.uppercased())
            .font(.system(size: 8.5, weight: .bold, design: .rounded))
            .kerning(1.4)
            .foregroundStyle(Color.black.opacity(0.46))
    }

    private func portRow(_ item: PortsStore.ListenerItem) -> some View {
        let profile = resolvedFriendlyProfile(for: item)
        let isExpanded = expandedItemID == item.id

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2.5) {
                    Text(verbatim: plainNumber(item.port))
                        .font(.system(size: 10.6, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.black.opacity(0.84))
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)

                    if settings.showResourceBadges {
                        portResourceMeta(for: item)
                    }
                }
                .frame(width: 64, alignment: .leading)

                VStack(alignment: .leading, spacing: 1.5) {
                    Text(profile.title)
                        .font(.system(size: 10.4, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.82))
                        .lineLimit(1)

                    Text(profile.subtitle)
                        .font(.system(size: 8.9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    HStack(spacing: 6) {
                        Text("\(tr("进程", "Process")) \(presentedProcessName(for: item))")
                        Text("PID \(item.pid)")
                        if let user = item.user, !user.isEmpty {
                            Text("\(tr("用户", "User")) \(user)")
                        }
                    }
                    .font(.system(size: 8.4, weight: .medium))
                    .foregroundStyle(.secondary.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                    if settings.showCommandLine,
                       let commandLine = item.commandLine,
                       !commandLine.isEmpty {
                        Text(commandLine)
                            .font(.system(size: 8.2, design: .monospaced))
                            .foregroundStyle(.secondary.opacity(0.86))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer(minLength: 0)

                if item.isNew {
                    Text(tr("新", "NEW"))
                        .font(.system(size: 8.3, weight: .bold))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.blue.opacity(0.11), in: Capsule())
                }

                if killInFlightPID == item.pid {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            expandedItemID = isExpanded ? nil : item.id
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8.8, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 1)
            .padding(.vertical, 8)
            .contentShape(Rectangle())

            if isExpanded {
                expandedInfoPanel(for: item)
                    .padding(.leading, 55)
                    .padding(.top, 2)
                    .padding(.bottom, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .contextMenu {
            Button(tr("复制访问地址", "Copy URL")) {
                copyURL(for: item)
            }

            Button(tr("复制 PID", "Copy PID")) {
                copyPID(for: item)
            }

            Button(tr("复制 kill 命令", "Copy kill command")) {
                copyKillCommand(for: item)
            }

            Divider()

            Button(tr("编辑可读说明", "Edit friendly note")) {
                requestInsightEdit(for: item)
            }

            Button(tr("保存为启动命令", "Save as startup command")) {
                saveStartupProfile(from: item)
            }
            .disabled(item.commandLine?.isEmpty ?? true)

            if settings.enableKill {
                Divider()

                Button(tr("结束进程", "Terminate Process"), role: .destructive) {
                    requestKillConfirmation(for: item)
                }
                .disabled(killInFlightPID != nil)
            }
        }
    }

    private func expandedInfoPanel(for item: PortsStore.ListenerItem) -> some View {
        let insight = listenerInsight(for: item)
        let resolvedKnowledge = knowledge.resolvedEntry(for: item)

        return VStack(alignment: .leading, spacing: 4) {
            if settings.showResourceBadges {
                detailLine(tr("资源", "Resources"), value: resourceSummaryText(for: item))
            }
            if let resolvedKnowledge {
                detailLine(
                    tr("注释范围", "Note Scope"),
                    value: resolvedKnowledge.scope.label(language: settings.appLanguage)
                )
            }
            detailLine(tr("项目", "Project"), value: insight.project)
            detailLine(tr("用途", "Purpose"), value: insight.purpose)
            detailLine(tr("来源", "Source"), value: insight.source)
            detailLine(tr("父链", "Parent"), value: insight.parentChain)
            if let hint = insight.hint {
                detailLine(tr("提示", "Hint"), value: hint)
            }

            HStack(spacing: 8) {
                Button(tr("复制 PID", "Copy PID")) {
                    copyPID(for: item)
                }
                .buttonStyle(.plain)
                .font(.system(size: 8.8, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.64))

                Button(tr("复制地址", "Copy URL")) {
                    copyURL(for: item)
                }
                .buttonStyle(.plain)
                .font(.system(size: 8.8, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.64))

                Button(tr("编辑说明", "Edit Note")) {
                    requestInsightEdit(for: item)
                }
                .buttonStyle(.plain)
                .font(.system(size: 8.8, weight: .semibold))
                .foregroundStyle(Color.blue.opacity(0.78))

                if settings.enableKill {
                    Button(tr("结束", "Terminate")) {
                        requestKillConfirmation(for: item)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 8.8, weight: .semibold))
                    .foregroundStyle(.red.opacity(0.82))
                    .disabled(killInFlightPID != nil)
                }

                Button(tr("保存启动项", "Save Startup")) {
                    saveStartupProfile(from: item)
                }
                .buttonStyle(.plain)
                .font(.system(size: 8.8, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.64))
                .disabled(item.commandLine?.isEmpty ?? true)
            }
            .padding(.top, 3)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 0.8)
        }
    }

    private func detailLine(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(title)
                .font(.system(size: 8.5, weight: .bold, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.48))

            Text(value)
                .font(.system(size: 8.9, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.7))
                .lineLimit(2)
        }
    }

    private func portResourceMeta(for item: PortsStore.ListenerItem) -> some View {
        HStack(spacing: 4) {
            HStack(spacing: 2) {
                Image(systemName: "cpu")
                    .font(.system(size: 6.6, weight: .semibold))
                Text(formattedCPUPercent(item.cpuUsagePercent))
                    .font(.system(size: 7.1, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            .foregroundStyle(cpuTint(for: item.cpuUsagePercent))

            Text("·")
                .font(.system(size: 6.5, weight: .bold))
                .foregroundStyle(Color.secondary.opacity(0.55))

            HStack(spacing: 2) {
                Image(systemName: "memorychip")
                    .font(.system(size: 6.6, weight: .semibold))
                Text(formattedMemoryCompact(item.memoryFootprintMB))
                    .font(.system(size: 7.1, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            .foregroundStyle(Color.purple.opacity(0.78))
        }
        .lineLimit(1)
        .minimumScaleFactor(0.78)
    }

    private func resourceSummaryText(for item: PortsStore.ListenerItem) -> String {
        "\(tr("CPU", "CPU")) \(formattedCPUPercent(item.cpuUsagePercent)) · \(tr("内存", "Memory")) \(formattedMemory(item.memoryFootprintMB))"
    }

    private func formattedCPUPercent(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(String(format: "%.1f", value))%"
    }

    private func formattedMemory(_ valueMB: Int?) -> String {
        guard let valueMB else { return "—" }
        return "\(plainNumber(valueMB)) MB"
    }

    private func formattedMemoryCompact(_ valueMB: Int?) -> String {
        guard let valueMB else { return "—" }
        if valueMB >= 1024 {
            let valueGB = Double(valueMB) / 1024
            return "\(String(format: "%.1f", valueGB))G"
        }
        return "\(plainNumber(valueMB))M"
    }

    private func cpuTint(for value: Double?) -> Color {
        guard let value else { return Color.blue.opacity(0.66) }
        if value >= 80 { return Color.red.opacity(0.84) }
        if value >= 40 { return Color.orange.opacity(0.86) }
        return Color.blue.opacity(0.76)
    }

    private func chartCoordinates(in size: CGSize) -> [CGPoint] {
        guard !history.isEmpty else { return [] }

        let values = history.map(\.value)
        let minimumValue = values.min() ?? 0
        let maximumValue = max(values.max() ?? 1, minimumValue + 1)
        let valueRange = maximumValue - minimumValue
        let totalPoints = max(history.count - 1, 1)
        let horizontalStep = size.width / CGFloat(totalPoints)

        return history.enumerated().map { index, point in
            let xPosition = CGFloat(index) * horizontalStep
            let normalized = (point.value - minimumValue) / valueRange
            let yPosition = size.height - (CGFloat(normalized) * (size.height - 6) + 3)
            return CGPoint(x: xPosition, y: yPosition)
        }
    }

    private func chartGrid(size: CGSize) -> some View {
        Path { path in
            let horizontalStep = size.height / 3
            for index in 0...3 {
                let yPosition = CGFloat(index) * horizontalStep
                path.move(to: CGPoint(x: 0, y: yPosition))
                path.addLine(to: CGPoint(x: size.width, y: yPosition))
            }
        }
        .stroke(Color.black.opacity(0.06), lineWidth: 1)
    }

    private func chartSmoothLinePath(points: [CGPoint]) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: first)
            addSplineCurves(to: &path, points: points)
        }
    }

    private func chartSmoothAreaPath(points: [CGPoint], size: CGSize) -> Path {
        Path { path in
            guard let first = points.first, let last = points.last else { return }
            path.move(to: CGPoint(x: first.x, y: size.height))
            path.addLine(to: first)
            addSplineCurves(to: &path, points: points)
            path.addLine(to: CGPoint(x: last.x, y: size.height))
            path.closeSubpath()
        }
    }

    private func addSplineCurves(to path: inout Path, points: [CGPoint]) {
        guard points.count > 1 else { return }
        if points.count == 2 {
            path.addLine(to: points[1])
            return
        }

        for index in 0..<(points.count - 1) {
            let p0 = index > 0 ? points[index - 1] : points[index]
            let p1 = points[index]
            let p2 = points[index + 1]
            let p3 = index + 2 < points.count ? points[index + 2] : p2

            let c1 = CGPoint(
                x: p1.x + (p2.x - p0.x) / 6,
                y: p1.y + (p2.y - p0.y) / 6
            )
            let c2 = CGPoint(
                x: p2.x - (p3.x - p1.x) / 6,
                y: p2.y - (p3.y - p1.y) / 6
            )
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
    }

    private func axisLabel(for date: Date?) -> String {
        guard let date else { return "--:--" }
        return date.formatted(date: .omitted, time: .shortened)
    }

    private func seedHistoryIfNeeded() {
        guard history.isEmpty else { return }
        let now = Date()
        history = (0..<14).map { offset in
            PortHistoryPoint(
                time: now.addingTimeInterval(TimeInterval(offset - 14) * 30),
                value: 0
            )
        }
    }

    private func appendHistoryPoint(force: Bool = false) {
        let now = Date()
        let nextValue = Double(totalUniquePortCount)

        if !force, let last = history.last {
            let interval = now.timeIntervalSince(last.time)
            if interval < 2.5 {
                history.removeLast()
            }
        }

        history.append(PortHistoryPoint(time: now, value: nextValue))

        let maxPoints = 28
        if history.count > maxPoints {
            history.removeFirst(history.count - maxPoints)
        }
    }

    private func friendlyProfile(for item: PortsStore.ListenerItem) -> (title: String, subtitle: String) {
        let process = item.processName.lowercased()

        switch process {
        case "ssh":
            return (tr("SSH 远程通道", "SSH Tunnel"), sshHint(for: item) ?? tr("用于远程登录或本地端口转发", "Used for remote login or local port forwarding"))
        case "node", "nodemon", "bun":
            return (tr("Node.js 本地服务", "Node.js Local Service"), usageHint(for: item.port))
        case "python", "python3":
            return (tr("Python 本地服务", "Python Local Service"), usageHint(for: item.port))
        case "java":
            return (tr("Java 应用服务", "Java App Service"), usageHint(for: item.port))
        case "ruby":
            return (tr("Ruby 应用服务", "Ruby App Service"), usageHint(for: item.port))
        case "go":
            return (tr("Go 应用服务", "Go App Service"), usageHint(for: item.port))
        case "postgres", "postmaster":
            return (tr("PostgreSQL 数据库", "PostgreSQL Database"), tr("数据库服务正在监听端口", "Database service is listening"))
        case "mysqld", "mysql":
            return (tr("MySQL 数据库", "MySQL Database"), tr("数据库服务正在监听端口", "Database service is listening"))
        case "redis-server", "redis":
            return (tr("Redis 缓存", "Redis Cache"), tr("缓存服务正在监听端口", "Cache service is listening"))
        case "mongod":
            return (tr("MongoDB 数据库", "MongoDB Database"), tr("数据库服务正在监听端口", "Database service is listening"))
        case "nginx":
            return (tr("Nginx 网站服务", "Nginx Web Service"), usageHint(for: item.port))
        case "httpd", "apache2":
            return (tr("Apache 网站服务", "Apache Web Service"), usageHint(for: item.port))
        case "docker":
            return (tr("Docker 服务", "Docker Service"), tr("容器平台相关服务", "Container platform related service"))
        default:
            return ("\(item.displayName) \(tr("服务", "Service"))", usageHint(for: item.port))
        }
    }

    private func resolvedFriendlyProfile(for item: PortsStore.ListenerItem) -> (title: String, subtitle: String) {
        let fallback = friendlyProfile(for: item)
        guard let resolved = knowledge.resolvedEntry(for: item) else {
            return fallback
        }

        return (
            title: resolved.entry.label ?? fallback.title,
            subtitle: resolved.entry.purpose ?? fallback.subtitle
        )
    }

    private func usageHint(for port: Int) -> String {
        switch port {
        case 22:
            return tr("SSH 远程连接端口", "SSH remote connection port")
        case 80:
            return tr("网站访问端口（HTTP）", "Web access port (HTTP)")
        case 443:
            return tr("安全网站端口（HTTPS）", "Secure web port (HTTPS)")
        case 3000...3999:
            return tr("常见本地开发端口", "Common local development port")
        case 5000...5999:
            return tr("常见后端或代理端口", "Common backend or proxy port")
        case 8000...8999:
            return tr("常见调试或测试端口", "Common debug or testing port")
        case 5432:
            return tr("PostgreSQL 默认端口", "PostgreSQL default port")
        case 3306, 33060:
            return tr("MySQL 默认端口", "MySQL default port")
        case 6379:
            return tr("Redis 默认端口", "Redis default port")
        case 27017:
            return tr("MongoDB 默认端口", "MongoDB default port")
        default:
            return tr("应用正在监听此端口", "Application is listening on this port")
        }
    }

    private func sshHint(for item: PortsStore.ListenerItem) -> String? {
        guard let commandLine = item.commandLine, !commandLine.isEmpty else {
            return tr("用于远程登录或隧道转发", "Used for remote login or tunnel forwarding")
        }

        if let host = sshRemoteHost(from: commandLine), !host.isEmpty {
            return tr("连接目标：\(host)", "Target host: \(host)")
        }

        return tr("用于远程登录或隧道转发", "Used for remote login or tunnel forwarding")
    }

    private func listenerInsight(for item: PortsStore.ListenerItem) -> (
        project: String,
        purpose: String,
        source: String,
        parentChain: String,
        hint: String?
    ) {
        let profile = resolvedFriendlyProfile(for: item)
        let process = item.processName.lowercased()
        let parentChain = parentChainText(for: item)
        let launchSource = item.launchSource ?? tr("未知来源", "Unknown source")

        if process == "ssh" {
            let host = item.commandLine.flatMap(sshRemoteHost) ?? tr("未知远端", "Unknown remote")
            let mapping = sshForwardMapping(for: item)
            let hint = settings.showCommandLine
                ? nil
                : tr("如需更精准定位隧道来源，可在设置开启“显示命令行”。", "Enable \"Show Command Line\" in Settings for more precise tunnel source tracing.")
            return (
                project: "\(tr("SSH 隧道", "SSH Tunnel")) · \(host)",
                purpose: profile.subtitle,
                source: mapping ?? tr("端口转发会话（来源：\(launchSource)）", "Port forwarding session (source: \(launchSource))"),
                parentChain: parentChain,
                hint: hint
            )
        }

        let project = item.commandLine.flatMap(inferProjectName(from:))
            ?? fallbackProjectName(for: item.processName)

        let source = item.commandLine.flatMap(sourceSummary(from:))
            ?? tr("命令详情已隐藏", "Command details are hidden")

        let hint: String? = settings.showCommandLine
            ? nil
            : tr("开启“显示命令行”可识别具体项目路径。", "Enable \"Show Command Line\" to identify exact project paths.")

        return (
            project: project,
            purpose: profile.subtitle,
            source: tr("\(source)（来源：\(launchSource)）", "\(source) (source: \(launchSource))"),
            parentChain: parentChain,
            hint: hint
        )
    }

    private func parentChainText(for item: PortsStore.ListenerItem) -> String {
        let current = "PID \(plainNumber(item.pid))"
        guard let ppid = item.ppid else {
            return tr("\(current) → 父进程未知", "\(current) → parent unknown")
        }

        let parentName = item.parentProcessName ?? tr("未知", "Unknown")
        return "\(current) → \(parentName) (\(plainNumber(ppid)))"
    }

    private func sshRemoteHost(from commandLine: String) -> String? {
        let tokens = commandLineTokens(commandLine)
        let endpoint = tokens.last { token in
            !token.hasPrefix("-") && token != "ssh" && token != "-N"
        }
        guard let endpoint else { return nil }

        let host = endpoint.split(separator: "@").last.map(String.init) ?? endpoint
        let cleaned = cleanToken(host)
        return cleaned.isEmpty ? nil : cleaned
    }

    private func sshForwardMapping(for item: PortsStore.ListenerItem) -> String? {
        guard let commandLine = item.commandLine, !commandLine.isEmpty else { return nil }
        let tokens = commandLineTokens(commandLine)

        var mappings: [String] = []
        var index = 0

        while index < tokens.count {
            let token = tokens[index]
            if token == "-L", index + 1 < tokens.count {
                mappings.append(cleanToken(tokens[index + 1]))
                index += 1
            } else if token.hasPrefix("-L"), token.count > 2 {
                mappings.append(cleanToken(String(token.dropFirst(2))))
            }
            index += 1
        }

        if let exact = mappings.first(where: { mapping in
            guard let left = mapping.split(separator: ":").first,
                  let localPort = Int(left) else { return false }
            return localPort == item.port
        }) {
            return tr("本地映射 \(exact)", "Local mapping \(exact)")
        }

        if let first = mappings.first {
            return tr("转发规则 \(first)", "Forward rule \(first)")
        }

        return nil
    }

    private func commandLineTokens(_ commandLine: String) -> [String] {
        commandLine
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
    }

    private func inferProjectName(from commandLine: String) -> String? {
        for token in commandLineTokens(commandLine) {
            guard let path = candidatePath(from: token) else { continue }
            let url = URL(fileURLWithPath: path)
            let folder = inferredFolderName(from: url)
            if let folder, !folder.isEmpty {
                return folder
            }
        }

        return nil
    }

    private func sourceSummary(from commandLine: String) -> String? {
        for token in commandLineTokens(commandLine) {
            guard let path = candidatePath(from: token) else { continue }
            if path.contains("/Users/") || path.contains("/Volumes/") {
                return path
            }
        }

        return commandLineTokens(commandLine).prefix(4).joined(separator: " ")
    }

    private func candidatePath(from rawToken: String) -> String? {
        let token = cleanToken(rawToken)
        guard !token.isEmpty else { return nil }

        if token.contains("=") {
            let parts = token.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                let valuePart = cleanToken(parts[1])
                if valuePart.contains("/") {
                    return valuePart
                }
            }
        }

        if token.contains("/") && !token.contains("@") {
            return token
        }

        return nil
    }

    private func inferredFolderName(from url: URL) -> String? {
        let ignored = Set(["usr", "bin", "sbin", "opt", "local", "Cellar", "Library", "System"])

        if !url.pathExtension.isEmpty {
            let parent = url.deletingLastPathComponent().lastPathComponent
            return ignored.contains(parent) ? nil : parent
        }

        let last = url.lastPathComponent
        return ignored.contains(last) ? nil : last
    }

    private func fallbackProjectName(for processName: String) -> String {
        let process = processName.lowercased()

        switch process {
        case "node", "nodemon", "bun":
            return tr("Node 本地项目", "Node Local Project")
        case "python", "python3":
            return tr("Python 本地项目", "Python Local Project")
        case "java":
            return tr("Java 应用", "Java App")
        case "ruby":
            return tr("Ruby 应用", "Ruby App")
        case "nginx", "httpd", "apache2":
            return tr("网站服务", "Web Service")
        case "postgres", "postmaster":
            return tr("PostgreSQL 数据库", "PostgreSQL Database")
        case "mysqld", "mysql":
            return tr("MySQL 数据库", "MySQL Database")
        case "redis", "redis-server":
            return tr("Redis 缓存服务", "Redis Cache Service")
        default:
            return tr("\(processName) 进程", "\(processName) process")
        }
    }

    private func cleanToken(_ token: String) -> String {
        token.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }

    private func requestInsightEdit(for item: PortsStore.ListenerItem) {
        let resolved = knowledge.resolvedEntry(for: item)
        let scope = resolved?.scope ?? .processPort
        let scopedEntry = knowledge.entry(for: item, scope: scope)

        pendingInsightScope = scope
        pendingInsightLabel = scopedEntry?.label ?? ""
        pendingInsightPurpose = scopedEntry?.purpose ?? ""
        pendingInsightItem = item
    }

    private func requestKillConfirmation(for item: PortsStore.ListenerItem) {
        guard killInFlightPID == nil else { return }
        pendingKillItem = item
    }

    private func performKill(for item: PortsStore.ListenerItem) {
        guard killInFlightPID == nil else { return }
        pendingKillItem = nil
        killInFlightPID = item.pid

        Task(priority: .userInitiated) {
            var killError: Error?

            do {
                try await terminateInBackground(pid: item.pid)
            } catch {
                killError = error
            }

            await scanner.rescanNow()

            await MainActor.run {
                if let killError {
                    showKillFeedback(killFailureMessage(for: item, error: killError), isError: true)
                } else if store.listeners.contains(where: { $0.pid == item.pid }) {
                    showKillFeedback(
                        tr(
                            "已尝试结束 \(presentedProcessName(for: item))（PID \(plainNumber(item.pid))），但它仍在运行。可能被守护进程自动拉起。",
                            "Tried terminating \(presentedProcessName(for: item)) (PID \(plainNumber(item.pid))), but it is still running. It may be auto-restarted by a supervisor."
                        ),
                        isError: true
                    )
                } else {
                    store.removeListeners(pid: item.pid)
                    if expandedItemID == item.id {
                        expandedItemID = nil
                    }
                    showKillFeedback(
                        tr(
                            "已结束 \(presentedProcessName(for: item))（PID \(plainNumber(item.pid))）",
                            "Terminated \(presentedProcessName(for: item)) (PID \(plainNumber(item.pid)))."
                        ),
                        isError: false
                    )
                }

                killInFlightPID = nil
            }
        }
    }

    private func terminateInBackground(pid: Int) async throws {
        try await Task.detached(priority: .userInitiated) {
            let actions = ProcessActions()
            try actions.terminate(pid: pid)
        }.value
    }

    private func sort(_ listeners: [PortsStore.ListenerItem]) -> [PortsStore.ListenerItem] {
        switch sortMode {
        case .byPort:
            return listeners
        case .byProcess:
            return listeners.sorted { left, right in
                let presentedLeft = presentedProcessName(for: left)
                let presentedRight = presentedProcessName(for: right)
                let processCompare = presentedLeft.localizedCaseInsensitiveCompare(presentedRight)
                if processCompare != .orderedSame {
                    return processCompare == .orderedAscending
                }

                if left.port != right.port {
                    return left.port < right.port
                }

                return left.pid < right.pid
            }
        case .byRecent:
            return listeners.sorted { left, right in
                if left.lastSeenAt != right.lastSeenAt {
                    return left.lastSeenAt > right.lastSeenAt
                }

                if left.firstSeenAt != right.firstSeenAt {
                    return left.firstSeenAt > right.firstSeenAt
                }

                if left.port != right.port {
                    return left.port < right.port
                }

                return left.pid < right.pid
            }
        }
    }

    private func copyURL(for item: PortsStore.ListenerItem) {
        let scheme = item.protocolName.lowercased().hasPrefix("tcp") ? "tcp" : item.protocolName.lowercased()
        let urlString = "\(scheme)://127.0.0.1:\(item.port)"
        writeToPasteboard(urlString)
    }

    private func copyPID(for item: PortsStore.ListenerItem) {
        writeToPasteboard(String(item.pid))
    }

    private func copyKillCommand(for item: PortsStore.ListenerItem) {
        writeToPasteboard("kill -TERM \(item.pid)")
    }

    private func saveStartupProfile(from item: PortsStore.ListenerItem) {
        let note = resolvedFriendlyProfile(for: item).subtitle
        let result = commands.addSuggestedProfile(
            preferredName: presentedProcessName(for: item),
            commandLine: item.commandLine,
            port: item.port,
            note: note
        )

        switch result {
        case .added(let name):
            showKillFeedback(tr("已加入启动命令：\(name)", "Added startup command: \(name)"), isError: false)
        case .updated(let name):
            showKillFeedback(tr("已更新启动命令说明：\(name)", "Updated startup note: \(name)"), isError: false)
        case .duplicate(let name):
            showKillFeedback(tr("启动命令已存在：\(name)", "Startup command already exists: \(name)"), isError: false)
        case .invalid(let reason):
            showKillFeedback(reason, isError: true)
        case .failed(let reason):
            showKillFeedback(reason, isError: true)
        }
    }

    private func requestPortEdit(for profile: CommandProfile) {
        pendingPortEditProfile = profile
        pendingPortEditValue = commands.inferredPort(for: profile).map(String.init) ?? ""
        pendingPortEditRestart = commands.isRunning(profile)
    }

    private func applyPortEdit(for profile: CommandProfile) {
        guard !portEditInFlight else { return }
        let rawValue = pendingPortEditValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let newPort = Int(rawValue) else {
            showKillFeedback(tr("请输入有效端口号。", "Please enter a valid port number."), isError: true)
            return
        }

        portEditInFlight = true

        Task {
            await performPortRebind(
                for: profile,
                newPort: newPort,
                restartIfRunning: pendingPortEditRestart,
                closeEditorOnSuccess: true
            )

            await MainActor.run {
                portEditInFlight = false
            }
        }
    }

    private func requestConflictFixConfirmation(_ suggestion: ConflictFixSuggestion) {
        guard !portEditInFlight else { return }
        pendingConflictFixSuggestion = suggestion
    }

    private func applyConflictSuggestion(_ suggestion: ConflictFixSuggestion) {
        guard !portEditInFlight else { return }
        portEditInFlight = true

        Task {
            await performPortRebind(
                for: suggestion.profile,
                newPort: suggestion.suggestedPort,
                restartIfRunning: true,
                closeEditorOnSuccess: false
            )

            await MainActor.run {
                pendingConflictFixSuggestion = nil
                portEditInFlight = false
            }
        }
    }

    private func performPortRebind(
        for profile: CommandProfile,
        newPort: Int,
        restartIfRunning: Bool,
        closeEditorOnSuccess: Bool
    ) async {
        let result = await commands.rebindPort(
            for: profile,
            to: newPort,
            restartIfRunning: restartIfRunning
        )

        await MainActor.run {
            switch result {
            case .updated(let name, let oldPort, let finalPort, let restarted, let strategy):
                if restarted {
                    let restartingMessage = tr(
                        "\(name) 端口 \(plainNumber(oldPort)) → \(plainNumber(finalPort)) · \(strategy.hint) · 正在健康检查…",
                        "\(name) port \(plainNumber(oldPort)) → \(plainNumber(finalPort)) · \(strategy.hint) · Running health checks..."
                    )
                    showKillFeedback(restartingMessage, isError: false)
                    startPortHealthCheck(
                        profileID: profile.id,
                        profileName: name,
                        oldPort: oldPort,
                        newPort: finalPort,
                        strategyHint: strategy.hint
                    )
                } else {
                    showKillFeedback(
                        tr(
                            "\(name) 端口 \(plainNumber(oldPort)) → \(plainNumber(finalPort)) · \(strategy.hint)",
                            "\(name) port \(plainNumber(oldPort)) → \(plainNumber(finalPort)) · \(strategy.hint)"
                        ),
                        isError: false
                    )
                }
                if closeEditorOnSuccess {
                    pendingPortEditProfile = nil
                }
                Task {
                    await scanner.rescanNow()
                }
            case .unchanged(let reason):
                showKillFeedback(reason, isError: false)
            case .invalid(let reason):
                showKillFeedback(reason, isError: true)
            case .failed(let reason):
                showKillFeedback(reason, isError: true)
            }
        }
    }

    private func startPortHealthCheck(
        profileID: String,
        profileName: String,
        oldPort: Int,
        newPort: Int,
        strategyHint: String
    ) {
        portHealthCheckTask?.cancel()
        portHealthCheckTask = Task {
            let isHealthy = await waitForPortHealth(
                profileID: profileID,
                expectedPort: newPort,
                maxAttempts: settings.healthCheckMaxAttempts.attempts,
                probeIntervalNanoseconds: settings.healthCheckProbeInterval.nanoseconds
            )
            guard !Task.isCancelled else { return }

            await MainActor.run {
                if isHealthy {
                    showKillFeedback(
                        tr(
                            "✅ \(profileName) 端口 \(plainNumber(oldPort)) → \(plainNumber(newPort))，健康检查通过 · \(strategyHint)",
                            "✅ \(profileName) port \(plainNumber(oldPort)) → \(plainNumber(newPort)), health check passed · \(strategyHint)"
                        ),
                        isError: false
                    )
                } else {
                    showKillFeedback(
                        tr(
                            "⚠️ \(profileName) 已改到 \(plainNumber(newPort))，但健康检查未通过。请检查服务日志或启动参数。",
                            "⚠️ \(profileName) changed to \(plainNumber(newPort)), but health checks failed. Please review logs or startup arguments."
                        ),
                        isError: true
                    )
                }
            }
        }
    }

    private func waitForPortHealth(
        profileID: String,
        expectedPort: Int,
        maxAttempts: Int,
        probeIntervalNanoseconds: UInt64
    ) async -> Bool {
        guard maxAttempts > 0 else { return false }

        for attempt in 0..<maxAttempts {
            await scanner.rescanNow()

            if isPortHealthy(profileID: profileID, expectedPort: expectedPort) {
                return true
            }

            if attempt < maxAttempts - 1 {
                try? await Task.sleep(nanoseconds: probeIntervalNanoseconds)
            }
        }

        return false
    }

    private func isPortHealthy(profileID: String, expectedPort: Int) -> Bool {
        let runningPID = commands.runningByProfileID[profileID].map { Int($0.pid) }
        if let runningPID {
            return store.listeners.contains { item in
                item.port == expectedPort && item.pid == runningPID
            }
        }

        return store.listeners.contains { item in
            item.port == expectedPort
        }
    }

    private func evaluateAutoProfileSuggestion(in listeners: [PortsStore.ListenerItem]) {
        guard settings.autoSuggestProfiles else { return }
        guard pendingAutoProfileSuggestion == nil else { return }

        for item in listeners {
            guard shouldAutoSuggestProfile(for: item) else { continue }
            pendingAutoProfileSuggestion = AutoProfileSuggestion(
                item: item,
                suggestedName: presentedProcessName(for: item)
            )
            break
        }
    }

    private func shouldAutoSuggestProfile(for item: PortsStore.ListenerItem) -> Bool {
        guard let commandLine = item.commandLine, !commandLine.isEmpty else { return false }
        guard commands.shouldSuggestProfile(commandLine: commandLine) else { return false }
        guard isLikelyUserProjectProcess(item) else { return false }
        guard !isManagedCommandPID(item.pid) else { return false }
        return true
    }

    private func isLikelyUserProjectProcess(_ item: PortsStore.ListenerItem) -> Bool {
        let process = item.processName.lowercased()

        let likelyProcesses: Set<String> = [
            "node", "nodemon", "bun", "python", "python3", "go", "php", "deno",
            "java", "ruby", "uvicorn", "gunicorn"
        ]
        if likelyProcesses.contains(process) { return true }

        guard let commandLine = item.commandLine?.lowercased() else { return false }
        if commandLine.contains("npm ")
            || commandLine.contains("pnpm ")
            || commandLine.contains("yarn ")
            || commandLine.contains("vite")
            || commandLine.contains("next")
            || commandLine.contains("nuxt")
            || commandLine.contains("tsx ")
            || commandLine.contains("ts-node")
            || commandLine.contains("uvicorn")
            || commandLine.contains("flask")
            || commandLine.contains("rails ")
            || commandLine.contains("docker compose") {
            return true
        }

        return false
    }

    private func isManagedCommandPID(_ pid: Int) -> Bool {
        commands.runningByProfileID.values.contains { running in
            Int(running.pid) == pid
        }
    }

    private func dismissAutoSuggestion(for suggestion: AutoProfileSuggestion) {
        commands.dismissSuggestion(for: suggestion.item.commandLine)
        pendingAutoProfileSuggestion = nil
    }

    private func acceptAutoSuggestion(_ suggestion: AutoProfileSuggestion) {
        let note = resolvedFriendlyProfile(for: suggestion.item).subtitle
        let result = commands.addSuggestedProfile(
            preferredName: suggestion.suggestedName,
            commandLine: suggestion.item.commandLine,
            port: suggestion.item.port,
            note: note
        )

        switch result {
        case .added(let name):
            showKillFeedback(tr("已加入启动命令：\(name)", "Added startup command: \(name)"), isError: false)
        case .updated(let name):
            showKillFeedback(tr("已更新启动命令说明：\(name)", "Updated startup note: \(name)"), isError: false)
        case .duplicate(let name):
            showKillFeedback(tr("启动命令已存在：\(name)", "Startup command already exists: \(name)"), isError: false)
        case .invalid(let reason):
            showKillFeedback(reason, isError: true)
        case .failed(let reason):
            showKillFeedback(reason, isError: true)
        }

        pendingAutoProfileSuggestion = nil
    }

    private func plainNumber(_ value: Int) -> String {
        String(value)
    }

    private func toggleSettingsFocus() {
        withAnimation(panelSwitchAnimation) {
            isSettingsExpanded.toggle()
            if isSettingsExpanded {
                settingsFocusedExpandedPanel = nil
            }
            hoveredSettingsPanel = nil
        }
    }

    private func nextAvailablePort(
        startingAt preferredPort: Int,
        occupied: Set<Int>,
        searchWindow: Int = 4000
    ) -> Int? {
        guard preferredPort <= 65_535 else { return nil }

        let lowerBound = max(preferredPort, 1024)
        let upperBound = min(65_535, lowerBound + searchWindow)

        for port in lowerBound...upperBound where !occupied.contains(port) {
            return port
        }

        return nil
    }

    private func showKillFeedback(_ message: String, isError: Bool) {
        killFeedbackTask?.cancel()
        withAnimation(feedbackBannerAnimation) {
            killFeedback = KillFeedback(message: message, isError: isError)
        }

        killFeedbackTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(feedbackBannerAnimation) {
                    killFeedback = nil
                }
            }
        }
    }

    private func exportSnapshot() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "portpilot-diagnostics-\(snapshotTimestampForFilename()).json"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.json]
        panel.title = tr("导出 PortPilot 诊断包", "Export PortPilot Diagnostics")
        panel.message = tr(
            "导出监听端口、命令场景、运行事件与扫描状态，便于排障。",
            "Export listeners, workspace commands, runtime events, and scanner state for diagnostics."
        )

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let payload: [String: Any] = [
            "generatedAt": ISO8601DateFormatter().string(from: Date()),
            "environment": [
                "hostName": ProcessInfo.processInfo.hostName,
                "osVersionString": ProcessInfo.processInfo.operatingSystemVersionString,
                "processorCount": ProcessInfo.processInfo.processorCount,
                "activeProcessorCount": ProcessInfo.processInfo.activeProcessorCount,
                "physicalMemoryBytes": ProcessInfo.processInfo.physicalMemory
            ],
            "summary": [
                "visibleListeners": store.listeners.count,
                "uniquePorts": Set(store.listeners.map(\.port)).count,
                "isUnknown": scanner.isUnknown,
                "consecutiveFailureCount": scanner.consecutiveFailureCount,
                "lastSuccessfulScanAt": scanner.lastSuccessfulScanAt.map {
                    ISO8601DateFormatter().string(from: $0)
                } ?? NSNull()
            ],
            "settings": [
                "appLanguage": settings.appLanguage.rawValue,
                "refreshIntervalSeconds": settings.refreshInterval.seconds,
                "countMode": settings.countMode.rawValue,
                "showCommandLine": settings.showCommandLine,
                "showResourceBadges": settings.showResourceBadges,
                "launchAtLogin": settings.launchAtLogin,
                "autoSuggestProfiles": settings.autoSuggestProfiles,
                "enableKill": settings.enableKill,
                "ignoredPortsText": settings.ignoredPortsText,
                "ignoredProcessesText": settings.ignoredProcessesText,
                "processAliasesText": settings.processAliasesText,
                "notifyOnNewPort": settings.notifyOnNewPort,
                "notifyOnPortConflict": settings.notifyOnPortConflict,
                "notifyOnScannerFailure": settings.notifyOnScannerFailure,
                "healthCheckMaxAttempts": settings.healthCheckMaxAttempts.attempts,
                "healthCheckProbeIntervalMs": settings.healthCheckProbeInterval.milliseconds
            ],
            "commands": [
                "profilesFilePath": commands.profilesFileURL.path,
                "workspaceOptions": workspaceOptions,
                "selectedWorkspace": selectedWorkspaceName.map { $0 as Any } ?? NSNull(),
                "scopedProfileCount": scopedProfiles.count,
                "scopedRunningCount": scopedRunningCount,
                "totalProfileCount": commands.profiles.count,
                "runningProfileCount": commands.runningByProfileID.count,
                "lastErrorMessage": commands.lastErrorMessage.map { $0 as Any } ?? NSNull(),
                "profiles": commands.profiles.map { profile in
                    [
                        "id": profile.id,
                        "name": profile.name,
                        "note": profile.note.map { $0 as Any } ?? NSNull(),
                        "cwd": profile.cwd,
                        "command": profile.command,
                        "ports": profile.ports,
                        "tags": profile.tags,
                        "env": profile.env,
                        "workspace": commands.workspaceName(for: profile).map { $0 as Any } ?? NSNull()
                    ] as [String: Any]
                },
                "recentEvents": commands.recentEvents.map { event in
                    [
                        "timestamp": ISO8601DateFormatter().string(from: event.timestamp),
                        "level": event.level.rawValue,
                        "message": event.message,
                        "profileName": event.profileName.map { $0 as Any } ?? NSNull()
                    ] as [String: Any]
                }
            ],
            "knowledge": [
                "entriesCount": knowledge.allEntries.count,
                "entries": knowledge.allEntries.map { entry in
                    [
                        "key": entry.key,
                        "label": entry.label.map { $0 as Any } ?? NSNull(),
                        "purpose": entry.purpose.map { $0 as Any } ?? NSNull(),
                        "source": entry.source.rawValue,
                        "updatedAt": ISO8601DateFormatter().string(from: entry.updatedAt)
                    ] as [String: Any]
                }
            ],
            "listeners": store.listeners.map { item in
                [
                    "port": item.port,
                    "protocol": item.protocolName,
                    "processName": item.processName,
                    "displayName": item.displayName,
                    "pid": item.pid,
                    "ppid": item.ppid.map { $0 as Any } ?? NSNull(),
                    "parentProcessName": item.parentProcessName.map { $0 as Any } ?? NSNull(),
                    "launchSource": item.launchSource.map { $0 as Any } ?? NSNull(),
                    "user": item.user.map { $0 as Any } ?? NSNull(),
                    "cpuUsagePercent": item.cpuUsagePercent.map { $0 as Any } ?? NSNull(),
                    "memoryFootprintMB": item.memoryFootprintMB.map { $0 as Any } ?? NSNull(),
                    "commandLine": settings.showCommandLine
                        ? (item.commandLine.map { $0 as Any } ?? NSNull())
                        : NSNull(),
                    "firstSeenAt": ISO8601DateFormatter().string(from: item.firstSeenAt),
                    "lastSeenAt": ISO8601DateFormatter().string(from: item.lastSeenAt),
                    "isNew": item.isNew
                ] as [String: Any]
            }
        ]

        do {
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url, options: .atomic)
            showKillFeedback(tr("已导出诊断包：\(url.lastPathComponent)", "Diagnostics exported: \(url.lastPathComponent)"), isError: false)
        } catch {
            showKillFeedback(tr("导出诊断失败：\(error.localizedDescription)", "Diagnostics export failed: \(error.localizedDescription)"), isError: true)
        }
    }

    private func snapshotTimestampForFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    private func killFailureMessage(for item: PortsStore.ListenerItem, error: Error) -> String {
        let defaultMessage = tr(
            "无法结束 \(presentedProcessName(for: item))（PID \(plainNumber(item.pid))）。",
            "Unable to terminate \(presentedProcessName(for: item)) (PID \(plainNumber(item.pid)))."
        )
        if let processError = error as? ProcessActionsError {
            return processError.localizedDescription(language: settings.appLanguage)
        }
        let details = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if details.isEmpty || details == "The operation couldn’t be completed." {
            return defaultMessage + tr(" 可能是权限不足，或该进程已由系统接管。", " Possible permission issue, or the process is managed by the system.")
        }
        return details
    }

    private func writeToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private func presentedProcessName(for item: PortsStore.ListenerItem) -> String {
        item.displayName
    }
}

private struct PortGauge: View {
    let value: Int

    private var clampedValue: Int {
        max(value, 0)
    }

    private var progress: Double {
        min(Double(clampedValue) / 60.0, 1)
    }

    var body: some View {
        ZStack {
            ZStack {
                Circle()
                    .trim(from: 0.15, to: 0.85)
                    .stroke(Color.black.opacity(0.11), style: StrokeStyle(lineWidth: 5.2, lineCap: .round))

                Circle()
                    .trim(from: 0.15, to: 0.15 + (0.7 * progress))
                    .stroke(
                        AngularGradient(
                            colors: [
                                Color(red: 0.16, green: 0.78, blue: 0.57),
                                Color(red: 0.2, green: 0.58, blue: 0.98),
                                Color(red: 0.66, green: 0.46, blue: 0.98),
                                Color(red: 1.0, green: 0.57, blue: 0.68)
                            ],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 5.2, lineCap: .round)
                    )
            }
            .rotationEffect(.degrees(180))
            .shadow(color: Color(red: 0.26, green: 0.49, blue: 0.9).opacity(0.23), radius: 5, y: 2)

            VStack(spacing: 0) {
                Text("\(clampedValue)")
                    .font(.system(size: 12.8, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.black.opacity(0.8))
                Text("Ports")
                    .font(.system(size: 7.6, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .offset(y: 2.2)
        }
    }
}

private struct UnifiedScrollVisualModifier: ViewModifier {
    let isDarkMode: Bool

    func body(content: Content) -> some View {
        content
            .scrollIndicators(.hidden)
            .overlay(alignment: .trailing) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isDarkMode ? 0.08 : 0.16),
                                Color.white.opacity(isDarkMode ? 0.22 : 0.42),
                                Color.white.opacity(isDarkMode ? 0.08 : 0.16)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 2.6)
                    .padding(.trailing, 1.5)
                    .padding(.vertical, 8)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .top) {
                LinearGradient(
                    colors: [
                        Color.white.opacity(isDarkMode ? 0.02 : 0.16),
                        .clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 10)
                .allowsHitTesting(false)
            }
            .overlay(alignment: .bottom) {
                LinearGradient(
                    colors: [
                        .clear,
                        Color.white.opacity(isDarkMode ? 0.02 : 0.16)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 10)
                .allowsHitTesting(false)
            }
    }
}

private extension View {
    func unifiedScrollVisual(isDarkMode: Bool) -> some View {
        modifier(UnifiedScrollVisualModifier(isDarkMode: isDarkMode))
    }
}

struct PortsView_Previews: PreviewProvider {
    static var previews: some View {
        let settings = SettingsStore()
        let store = PortsStore(settingsStore: settings)
        let scanner = PortsScanner(store: store, settingsStore: settings)
        let commands = CommandProfilesStore()
        let knowledge = PortKnowledgeStore()

        store.applyScan([
            PortListener(
                processName: "node",
                pid: 43210,
                port: 3000,
                user: "sean",
                protocolName: "TCP",
                commandLine: "node server.js --port 3000",
                ppid: 43100,
                parentProcessName: "zsh",
                launchSource: "Terminal",
                cpuUsagePercent: 23.4,
                memoryFootprintMB: 312
            ),
            PortListener(
                processName: "ssh",
                pid: 51234,
                port: 8000,
                user: "sean",
                protocolName: "TCP",
                commandLine: "ssh -N -L 8000:127.0.0.1:80 user@prod.example.com",
                ppid: 1,
                parentProcessName: "launchd",
                launchSource: "ssh",
                cpuUsagePercent: 1.3,
                memoryFootprintMB: 42
            ),
            PortListener(
                processName: "postgres",
                pid: 900,
                port: 5432,
                user: "sean",
                protocolName: "TCP",
                commandLine: nil,
                ppid: 1,
                parentProcessName: "launchd",
                launchSource: "brew",
                cpuUsagePercent: 8.6,
                memoryFootprintMB: 188
            )
        ])

        return PortsView(store: store, settings: settings, scanner: scanner, commands: commands, knowledge: knowledge)
            .frame(width: 396)
    }
}
