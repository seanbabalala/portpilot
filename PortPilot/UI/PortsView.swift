import AppKit
import Foundation
import SwiftUI

struct PortsView: View {
    private enum SortMode: String, CaseIterable, Identifiable {
        case byPort = "Port"
        case byProcess = "Process"
        case byRecent = "Recent"

        var id: String { rawValue }
    }

    private enum BentoTone {
        case pearl
        case sky
        case mint
        case peach
    }

    private struct PortHistoryPoint: Identifiable {
        let id = UUID()
        let time: Date
        let value: Double
    }

    @ObservedObject var store: PortsStore
    @ObservedObject var settings: SettingsStore
    @ObservedObject var scanner: PortsScanner

    @State private var searchText: String = ""
    @State private var sortMode: SortMode = .byPort
    @State private var history: [PortHistoryPoint] = []
    @State private var isSettingsExpanded: Bool = false
    @State private var pendingKillItem: PortsStore.ListenerItem?
    @State private var isKillConfirmPresented: Bool = false
    @State private var killErrorMessage: String = ""
    @State private var isKillErrorPresented: Bool = false
    @State private var killInFlightPID: Int?

    private var query: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isFiltering: Bool {
        !query.isEmpty
    }

    private var filteredListeners: [PortsStore.ListenerItem] {
        let filtered = store.listeners.filter { item in
            guard !query.isEmpty else { return true }

            let profile = friendlyProfile(for: item)
            return item.processName.localizedCaseInsensitiveContains(query)
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

    private var statusText: String {
        if scanner.isUnknown { return "状态异常" }
        return "运行正常"
    }

    private var statusTint: Color {
        scanner.isUnknown ? .orange : Color(red: 0.12, green: 0.66, blue: 0.45)
    }

    private var countLabel: String {
        if isFiltering {
            return "\(filteredListeners.count) / \(store.listeners.count) items"
        }
        return "\(filteredListeners.count) items"
    }

    private var listHeight: CGFloat {
        isSettingsExpanded ? 166 : 214
    }

    private var lastScanText: String {
        guard let lastScanAt = scanner.lastSuccessfulScanAt else {
            return "等待首次扫描"
        }
        return lastScanAt.formatted(date: .omitted, time: .standard)
    }

    private var modeText: String {
        switch settings.countMode {
        case .portAndPID:
            return "按实例"
        case .portOnly:
            return "按端口"
        }
    }

    var body: some View {
        ZStack {
            backgroundLayer
            panel
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
        }
        .frame(width: 396)
        .confirmationDialog(
            "确认结束进程",
            isPresented: $isKillConfirmPresented,
            titleVisibility: .visible,
            presenting: pendingKillItem
        ) { item in
            Button("结束进程", role: .destructive) {
                performKill(for: item)
            }
            Button("取消", role: .cancel) {
                pendingKillItem = nil
            }
        } message: { item in
            Text("进程：\(item.processName) · PID：\(item.pid) · 端口：\(item.port)")
        }
        .alert("结束失败", isPresented: $isKillErrorPresented) {
            Button("好的", role: .cancel) {}
        } message: {
            Text(killErrorMessage)
        }
        .onAppear {
            seedHistoryIfNeeded()
            appendHistoryPoint(force: true)
        }
        .onChange(of: store.listeners) {
            appendHistoryPoint()
        }
        .onChange(of: settings.countMode) {
            store.updateCountMode(settings.countMode)
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.84), value: isSettingsExpanded)
    }

    private var backgroundLayer: some View {
        LinearGradient(
            colors: [
                Color(red: 0.985, green: 0.982, blue: 0.97),
                Color(red: 0.956, green: 0.978, blue: 0.988),
                Color(red: 0.966, green: 0.988, blue: 0.972)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(Color(red: 0.48, green: 0.68, blue: 0.99).opacity(0.18))
                .frame(width: 188, height: 188)
                .blur(radius: 14)
                .offset(x: 36, y: -28)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .bottomLeading) {
            Circle()
                .fill(Color(red: 0.34, green: 0.86, blue: 0.72).opacity(0.14))
                .frame(width: 162, height: 162)
                .blur(radius: 16)
                .offset(x: -34, y: 30)
                .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }

    private var panel: some View {
        VStack(spacing: 10) {
            heroSection
            metricsBentoSection
            controlsSection

            if isSettingsExpanded {
                settingsBentoSection
            }

            listSection
            trendSection
            footerSection
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.8),
                            Color.white.opacity(0.56)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .white.opacity(0.9), radius: 2, y: -1)
        )
        .shadow(color: Color(red: 0.22, green: 0.37, blue: 0.58).opacity(0.16), radius: 24, y: 14)
        .shadow(color: .black.opacity(0.08), radius: 12, y: 5)
    }

    private var heroSection: some View {
        bentoCard(.pearl) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("PORTPILOT")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .kerning(1.5)
                        .foregroundStyle(Color.black.opacity(0.45))

                    Text("Port Command Center")
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

                    Text("Last scan · \(lastScanText)")
                        .font(.system(size: 9.4, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.52))
                }

                Spacer(minLength: 8)

                VStack(spacing: 8) {
                    Button {
                        withAnimation {
                            isSettingsExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: isSettingsExpanded ? "xmark" : "slider.horizontal.3")
                            .font(.system(size: 10.6, weight: .semibold))
                            .foregroundStyle(Color.black.opacity(0.72))
                            .frame(width: 26, height: 26)
                            .background(.white.opacity(0.74), in: Circle())
                    }
                    .buttonStyle(.plain)

                    PortGauge(value: totalUniquePortCount)
                        .frame(width: 82, height: 61)
                }
            }
        }
    }

    private var metricsBentoSection: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                bentoCard(.sky) {
                    metricTitle("Listeners")
                    Text("\(filteredListeners.count)")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.black.opacity(0.82))
                    Text(countLabel)
                        .font(.system(size: 9.2, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                bentoCard(.mint) {
                    metricTitle("Occupied Ports")
                    Text("\(isFiltering ? uniquePortCount : totalUniquePortCount)")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.black.opacity(0.82))
                    Text(isFiltering ? "filtered view" : "global view")
                        .font(.system(size: 9.2, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                bentoCard(.peach) {
                    metricTitle("Refresh")
                    Text(settings.refreshInterval.label)
                        .font(.system(size: 13.2, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.8))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                bentoCard(.pearl) {
                    metricTitle("Count Mode")
                    Text(modeText)
                        .font(.system(size: 13.2, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.8))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
    }

    private var controlsSection: some View {
        bentoCard(.pearl) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)

                    TextField("Search port / process / pid", text: $searchText)
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
                .background(Color.white.opacity(0.72), in: Capsule())

                Menu {
                    ForEach(SortMode.allCases) { mode in
                        Button {
                            sortMode = mode
                        } label: {
                            if mode == sortMode {
                                Label(mode.rawValue, systemImage: "checkmark")
                            } else {
                                Text(mode.rawValue)
                            }
                        }
                    }
                } label: {
                    Text(sortMode.rawValue)
                        .font(.system(size: 10.4, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.74))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.white.opacity(0.72), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var settingsBentoSection: some View {
        HStack(spacing: 8) {
            bentoCard(.sky) {
                Text("SETTINGS")
                    .font(.system(size: 8.6, weight: .bold, design: .rounded))
                    .kerning(1.6)
                    .foregroundStyle(Color.black.opacity(0.44))

                VStack(spacing: 7) {
                    settingPickerRow(title: "刷新频率", contentWidth: 88) {
                        Picker("", selection: $settings.refreshInterval) {
                            ForEach(RefreshIntervalOption.allCases) { option in
                                Text(option.label).tag(option)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .controlSize(.small)
                    }

                    settingPickerRow(title: "统计方式", contentWidth: 120) {
                        Picker("", selection: $settings.countMode) {
                            Text("按实例").tag(PortCountMode.portAndPID)
                            Text("按端口").tag(PortCountMode.portOnly)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                    }
                }
                .padding(.top, 4)
            }

            bentoCard(.mint) {
                Text("DISPLAY")
                    .font(.system(size: 8.6, weight: .bold, design: .rounded))
                    .kerning(1.6)
                    .foregroundStyle(Color.black.opacity(0.44))

                VStack(spacing: 8) {
                    settingToggleRow(title: "显示命令行", isOn: $settings.showCommandLine)
                    settingToggleRow(title: "允许结束进程", isOn: $settings.enableKill)
                }
                .padding(.top, 5)
            }
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func settingPickerRow<Content: View>(
        title: String,
        contentWidth: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 9.8, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.68))
            Spacer(minLength: 8)
            content()
                .frame(width: contentWidth)
        }
    }

    private func settingToggleRow(title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 9.8, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.68))
            Spacer(minLength: 8)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
    }

    private var listSection: some View {
        bentoCard(.pearl) {
            HStack {
                Text("Ports")
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
                    Text("No listeners")
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
                .scrollIndicators(.hidden)
                .frame(height: listHeight)
            }
        }
    }

    private var trendSection: some View {
        bentoCard(.sky) {
            HStack {
                Text("Smooth Trend")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.82))
                Spacer()
                Text("global occupied ports")
                    .font(.system(size: 8.8, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 3)

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
            .frame(height: 94)

            HStack {
                Text(axisLabel(for: history.first?.time))
                Spacer()
                Text(axisLabel(for: history.last?.time))
            }
            .font(.system(size: 9.2, weight: .medium))
            .foregroundStyle(.secondary)
        }
    }

    private var footerSection: some View {
        HStack(spacing: 8) {
            Label(
                settings.enableKill ? "Kill 已开启" : "Kill 已关闭",
                systemImage: settings.enableKill ? "bolt.trianglebadge.exclamationmark.fill" : "bolt.slash"
            )
            .font(.system(size: 9.4, weight: .semibold))
            .foregroundStyle(settings.enableKill ? Color(red: 0.18, green: 0.63, blue: 0.42) : .secondary)

            Spacer()

            Button {
                withAnimation {
                    isSettingsExpanded.toggle()
                }
            } label: {
                Image(systemName: isSettingsExpanded ? "slider.horizontal.3" : "gearshape")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .background(Color.white.opacity(0.7), in: Circle())
            }
            .buttonStyle(.plain)

            Button {
                Task { await scanner.rescanNow() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .background(Color.white.opacity(0.7), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(scanner.isScanning)

            Button(role: .destructive) {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .background(Color.white.opacity(0.7), in: Circle())
            }
            .buttonStyle(.plain)
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
        .background(cardFill(tone), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(0.045), radius: 8, y: 4)
    }

    private func cardFill(_ tone: BentoTone) -> LinearGradient {
        switch tone {
        case .pearl:
            return LinearGradient(
                colors: [
                    Color.white.opacity(0.82),
                    Color.white.opacity(0.58)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .sky:
            return LinearGradient(
                colors: [
                    Color(red: 0.86, green: 0.93, blue: 1.0).opacity(0.86),
                    Color(red: 0.92, green: 0.96, blue: 1.0).opacity(0.6)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .mint:
            return LinearGradient(
                colors: [
                    Color(red: 0.86, green: 0.97, blue: 0.93).opacity(0.84),
                    Color(red: 0.93, green: 0.98, blue: 0.96).opacity(0.62)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .peach:
            return LinearGradient(
                colors: [
                    Color(red: 1.0, green: 0.93, blue: 0.86).opacity(0.86),
                    Color(red: 1.0, green: 0.96, blue: 0.92).opacity(0.64)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private func metricTitle(_ value: String) -> some View {
        Text(value.uppercased())
            .font(.system(size: 8.5, weight: .bold, design: .rounded))
            .kerning(1.4)
            .foregroundStyle(Color.black.opacity(0.46))
    }

    private func portRow(_ item: PortsStore.ListenerItem) -> some View {
        let profile = friendlyProfile(for: item)

        return HStack(spacing: 10) {
            Text("\(item.port)")
                .font(.system(size: 10.6, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.black.opacity(0.84))
                .lineLimit(1)
                .minimumScaleFactor(0.62)
                .frame(width: 56, alignment: .leading)

            VStack(alignment: .leading, spacing: 1.5) {
                Text(item.processName)
                    .font(.system(size: 10.4, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.82))
                    .lineLimit(1)

                Text("PID \(item.pid) · \(profile.subtitle)")
                    .font(.system(size: 8.9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            Spacer(minLength: 0)

            if item.isNew {
                Text("NEW")
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
                Image(systemName: "chevron.right")
                    .font(.system(size: 8.8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 1)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .contextMenu {
            Button("复制访问地址") {
                copyURL(for: item)
            }

            Button("复制 PID") {
                copyPID(for: item)
            }

            Button("复制 kill 命令") {
                copyKillCommand(for: item)
            }

            if settings.enableKill {
                Divider()

                Button("结束进程", role: .destructive) {
                    requestKillConfirmation(for: item)
                }
                .disabled(killInFlightPID != nil)
            }
        }
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
            return ("SSH Tunnel", sshHint(for: item) ?? "Secure remote forwarding")
        case "node", "nodemon", "bun":
            return ("Node.js Service", usageHint(for: item.port))
        case "python", "python3":
            return ("Python Service", usageHint(for: item.port))
        case "postgres", "postmaster":
            return ("PostgreSQL", "Database listener")
        case "mysqld", "mysql":
            return ("MySQL", "Database listener")
        case "redis-server", "redis":
            return ("Redis", "Cache listener")
        case "nginx":
            return ("Nginx", usageHint(for: item.port))
        case "httpd", "apache2":
            return ("Apache", usageHint(for: item.port))
        default:
            return ("\(item.processName) Service", usageHint(for: item.port))
        }
    }

    private func usageHint(for port: Int) -> String {
        switch port {
        case 22:
            return "SSH"
        case 80:
            return "HTTP"
        case 443:
            return "HTTPS"
        case 3000...3999:
            return "Local development"
        case 5000...5999:
            return "Proxy/backend"
        case 8000...8999:
            return "Debug service"
        case 5432:
            return "PostgreSQL default"
        case 3306, 33060:
            return "MySQL default"
        case 6379:
            return "Redis default"
        case 27017:
            return "MongoDB default"
        default:
            return "Listening port"
        }
    }

    private func sshHint(for item: PortsStore.ListenerItem) -> String? {
        guard let commandLine = item.commandLine, !commandLine.isEmpty else {
            return "SSH forwarding/session"
        }

        let tokens = commandLine.split(whereSeparator: \.isWhitespace).map(String.init)
        let endpoint = tokens.last { token in
            !token.hasPrefix("-") && token != "ssh" && token != "-N"
        }

        if let endpoint {
            let host = endpoint.split(separator: "@").last.map(String.init) ?? endpoint
            if !host.isEmpty {
                return "Target: \(host)"
            }
        }

        return "SSH forwarding/session"
    }

    private func requestKillConfirmation(for item: PortsStore.ListenerItem) {
        guard killInFlightPID == nil else { return }
        pendingKillItem = item
        isKillConfirmPresented = true
    }

    private func performKill(for item: PortsStore.ListenerItem) {
        guard killInFlightPID == nil else { return }
        pendingKillItem = nil
        killInFlightPID = item.pid

        Task(priority: .userInitiated) {
            do {
                try await terminateInBackground(pid: item.pid)
                await MainActor.run {
                    store.removeListeners(pid: item.pid)
                }
                await scanner.rescanNow()
            } catch {
                await MainActor.run {
                    killErrorMessage = error.localizedDescription
                    isKillErrorPresented = true
                }
            }

            await MainActor.run {
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
                let processCompare = left.processName.localizedCaseInsensitiveCompare(right.processName)
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

    private func writeToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
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
                    .stroke(Color.black.opacity(0.11), style: StrokeStyle(lineWidth: 6, lineCap: .round))

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
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
            }
            .rotationEffect(.degrees(180))
            .shadow(color: Color(red: 0.26, green: 0.49, blue: 0.9).opacity(0.23), radius: 5, y: 2)

            VStack(spacing: 0) {
                Text("\(clampedValue)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.black.opacity(0.8))
                Text("Ports")
                    .font(.system(size: 8.2, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .offset(y: 2.5)
        }
    }
}

struct PortsView_Previews: PreviewProvider {
    static var previews: some View {
        let settings = SettingsStore()
        let store = PortsStore(settingsStore: settings)
        let scanner = PortsScanner(store: store, settingsStore: settings)

        store.applyScan([
            PortListener(processName: "node", pid: 43210, port: 3000, user: "sean", protocolName: "TCP", commandLine: "node server.js --port 3000"),
            PortListener(processName: "ssh", pid: 51234, port: 8000, user: "sean", protocolName: "TCP", commandLine: "ssh -N -L 8000:127.0.0.1:80 user@prod.example.com"),
            PortListener(processName: "postgres", pid: 900, port: 5432, user: "sean", protocolName: "TCP", commandLine: nil)
        ])

        return PortsView(store: store, settings: settings, scanner: scanner)
            .frame(width: 396)
    }
}
