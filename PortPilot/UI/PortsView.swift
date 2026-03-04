import AppKit
import SwiftUI

struct PortsView: View {
    @Environment(\.openSettings) private var openSettings

    @ObservedObject var store: PortsStore
    @ObservedObject var settings: SettingsStore
    @ObservedObject var scanner: PortsScanner

    @State private var searchText: String = ""
    @State private var hoveredRowID: String?
    @State private var pendingKillItem: PortsStore.ListenerItem?
    @State private var isKillConfirmPresented: Bool = false
    @State private var killErrorMessage: String = ""
    @State private var isKillErrorPresented: Bool = false

    private let processActions = ProcessActions()

    private var filteredListeners: [PortsStore.ListenerItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return store.listeners }

        return store.listeners.filter { item in
            let profile = friendlyProfile(for: item)
            return item.processName.localizedCaseInsensitiveContains(query)
                || String(item.port).contains(query)
                || String(item.pid).contains(query)
                || (item.user?.localizedCaseInsensitiveContains(query) ?? false)
                || profile.title.localizedCaseInsensitiveContains(query)
                || profile.subtitle.localizedCaseInsensitiveContains(query)
                || (settings.showCommandLine && (item.commandLine?.localizedCaseInsensitiveContains(query) ?? false))
        }
    }

    private var statusText: String {
        scanner.isUnknown ? "状态异常" : "运行正常"
    }

    private var statusTint: Color {
        scanner.isUnknown ? .orange : .green
    }

    private var countModeText: String {
        settings.countMode == .portAndPID ? "实例计数" : "端口计数"
    }

    var body: some View {
        VStack(spacing: 8) {
            titleRow
            chipsRow
            searchRow
            listenersPanel
            footerRow
        }
        .padding(10)
        .frame(width: 428, height: 512)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.22), lineWidth: 1)
        }
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
    }

    private var titleRow: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Label("PortPilot 端口雷达", systemImage: "dot.radiowaves.left.and.right")
                    .font(.system(size: 15.5, weight: .semibold))

                Text("自动解释常见端口用途（更适合小白）")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(scanner.summaryText)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .monospacedDigit()

                HStack(spacing: 5) {
                    Circle()
                        .fill(statusTint)
                        .frame(width: 6, height: 6)
                    Text(statusText)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(statusTint)
                }
            }
        }
        .padding(.horizontal, 2)
    }

    private var chipsRow: some View {
        HStack(spacing: 6) {
            chip(systemImage: "clock", text: "每 \(settings.refreshInterval.seconds) 秒刷新")
            chip(systemImage: "sum", text: countModeText)
            Spacer()
            Text("\(filteredListeners.count)/\(store.listeners.count)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.16), lineWidth: 1)
        }
    }

    private var searchRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("搜索：端口 / 进程 / 用途 / PID", text: $searchText)
                .textFieldStyle(.plain)

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
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.16), lineWidth: 1)
        }
    }

    private var listenersPanel: some View {
        Group {
            if filteredListeners.isEmpty {
                VStack(spacing: 7) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                    Text("没有匹配结果")
                        .font(.headline)
                    Text("换个关键词试试")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 5) {
                        ForEach(filteredListeners) { item in
                            listenerRow(item)
                        }
                    }
                    .padding(1)
                }
                .scrollIndicators(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(6)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.16), lineWidth: 1)
        }
    }

    private var footerRow: some View {
        HStack(spacing: 8) {
            Button {
                openSettings()
            } label: {
                Label("设置", systemImage: "gearshape")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button(role: .destructive) {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("退出", systemImage: "power")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .keyboardShortcut("q")
        }
        .padding(7)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.16), lineWidth: 1)
        }
    }

    private func listenerRow(_ item: PortsStore.ListenerItem) -> some View {
        let profile = friendlyProfile(for: item)

        return HStack(spacing: 8) {
            Text("\(item.port)")
                .font(.system(.callout, design: .monospaced).weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(profile.title)
                    .font(.system(size: 12.8, weight: .semibold))
                    .lineLimit(1)

                Text(profile.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 7) {
                    Text("PID \(item.pid)")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)

                    if let user = item.user, !user.isEmpty {
                        Text("用户 \(user)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Text("原始 \(item.processName)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if settings.showCommandLine,
                   let commandLine = item.commandLine,
                   !commandLine.isEmpty {
                    Text(commandLine)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 6)

            if item.isNew {
                Text("NEW")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.green.opacity(0.18), in: Capsule())
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(
                    hoveredRowID == item.id ? Color.accentColor.opacity(0.52) : Color.secondary.opacity(0.18),
                    lineWidth: 1
                )
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                if hovering {
                    hoveredRowID = item.id
                } else if hoveredRowID == item.id {
                    hoveredRowID = nil
                }
            }
        }
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
            }
        }
    }

    private func friendlyProfile(for item: PortsStore.ListenerItem) -> (title: String, subtitle: String) {
        let process = item.processName.lowercased()

        switch process {
        case "ssh":
            return ("SSH 隧道", sshHint(for: item) ?? "用于安全连接远程服务器")
        case "node", "nodemon", "bun":
            return ("Node.js 服务", usageHint(for: item.port))
        case "python", "python3":
            return ("Python 服务", usageHint(for: item.port))
        case "postgres", "postmaster":
            return ("PostgreSQL 数据库", "数据库服务端口（常见于本地开发）")
        case "mysqld", "mysql":
            return ("MySQL 数据库", "数据库服务端口（常见于本地开发）")
        case "redis-server", "redis":
            return ("Redis 缓存", "缓存服务端口")
        case "nginx":
            return ("Nginx Web 服务", usageHint(for: item.port))
        case "httpd", "apache2":
            return ("Apache Web 服务", usageHint(for: item.port))
        default:
            return ("\(item.processName) 服务", usageHint(for: item.port))
        }
    }

    private func usageHint(for port: Int) -> String {
        switch port {
        case 22:
            return "SSH 远程登录端口"
        case 80:
            return "网站访问端口（HTTP）"
        case 443:
            return "安全网站访问端口（HTTPS）"
        case 3000...3999:
            return "本地开发常用端口"
        case 5000...5999:
            return "本地服务/代理常用端口"
        case 8000...8999:
            return "本地调试常用端口"
        case 5432:
            return "PostgreSQL 默认端口"
        case 3306, 33060:
            return "MySQL 默认端口"
        case 6379:
            return "Redis 默认端口"
        case 27017:
            return "MongoDB 默认端口"
        default:
            return "应用正在监听此端口"
        }
    }

    private func sshHint(for item: PortsStore.ListenerItem) -> String? {
        guard let commandLine = item.commandLine, !commandLine.isEmpty else {
            return "SSH 本地端口转发/远程连接"
        }

        let tokens = commandLine.split(whereSeparator: \.isWhitespace).map(String.init)
        let endpoint = tokens.last { token in
            !token.hasPrefix("-") && token != "ssh" && token != "-N"
        }

        if let endpoint {
            let host = endpoint.split(separator: "@").last.map(String.init) ?? endpoint
            if !host.isEmpty {
                return "连接目标：\(host)"
            }
        }

        return "SSH 本地端口转发/远程连接"
    }

    private func chip(systemImage: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
            Text(text)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private func requestKillConfirmation(for item: PortsStore.ListenerItem) {
        pendingKillItem = item
        isKillConfirmPresented = true
    }

    private func performKill(for item: PortsStore.ListenerItem) {
        pendingKillItem = nil

        do {
            try processActions.terminate(pid: item.pid)
        } catch {
            killErrorMessage = error.localizedDescription
            isKillErrorPresented = true
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
            .frame(width: 428, height: 512)
    }
}
