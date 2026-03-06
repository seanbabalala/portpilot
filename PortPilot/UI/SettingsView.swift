import AppKit
import SwiftUI

struct SettingsView: View {
    private enum CardTone {
        case sky
        case mint
        case pearl
    }

    @ObservedObject var settings: SettingsStore
    @Environment(\.colorScheme) private var colorScheme

    private var isDarkMode: Bool {
        colorScheme == .dark
    }

    private func tr(_ chinese: String, _ english: String) -> String {
        settings.tr(chinese, english)
    }

    var body: some View {
        ZStack {
            backgroundLayer

            VStack(spacing: 0) {
                topBar
                Divider().opacity(0.12)
                ScrollView {
                    VStack(spacing: 10) {
                        scanCard
                        safetyCard
                        displayRuleCard
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                }
                .scrollIndicators(.hidden)
            }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(isDarkMode ? 0.22 : 0.82), lineWidth: 0.9)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.black.opacity(isDarkMode ? 0.22 : 0.06), lineWidth: 0.55)
            }
            .padding(10)
            .shadow(color: .black.opacity(isDarkMode ? 0.32 : 0.12), radius: 22, y: 12)
        }
        .frame(width: 420, height: 560)
    }

    private var backgroundLayer: some View {
        ZStack {
            LinearGradient(
                colors: isDarkMode
                    ? [
                        Color(red: 0.16, green: 0.2, blue: 0.28),
                        Color(red: 0.13, green: 0.17, blue: 0.24)
                    ]
                    : [
                        Color(red: 0.995, green: 0.997, blue: 1.0),
                        Color(red: 0.976, green: 0.989, blue: 1.0)
                    ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.blue.opacity(isDarkMode ? 0.2 : 0.18))
                .frame(width: 250, height: 250)
                .blur(radius: 30)
                .offset(x: 150, y: -120)

            Circle()
                .fill(Color.mint.opacity(isDarkMode ? 0.16 : 0.18))
                .frame(width: 220, height: 220)
                .blur(radius: 30)
                .offset(x: -170, y: 150)
        }
        .ignoresSafeArea()
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.blue.opacity(0.84))
                .frame(width: 28, height: 28)
                .background(Color.white.opacity(0.56), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(tr("PortPilot 设置", "PortPilot Settings"))
                    .font(.system(size: 14.5, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.primary.opacity(0.9))
                Text(tr("扫描、健康检查、安全与规则", "Scanning, health checks, safety and rules"))
                    .font(.system(size: 10.2, weight: .medium))
                    .foregroundStyle(Color.secondary.opacity(0.9))
            }

            Spacer()

            Button {
                NSApp.keyWindow?.close()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.primary.opacity(0.72))
                    .frame(width: 24, height: 24)
                    .background(Color.white.opacity(0.56), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var scanCard: some View {
        settingsCard(
            title: tr("扫描与健康检查", "Scan & Health Check"),
            subtitle: tr("控制刷新频率、统计口径与改端口后的自动探测", "Control refresh rate, counting mode, and post-change probes"),
            icon: "waveform.path.ecg",
            tone: .sky
        ) {
            pickerRow(title: tr("语言", "Language"), subtitle: tr("全局文案显示语言", "Global UI language")) {
                Picker("", selection: $settings.appLanguage) {
                    Text(tr("中文", "CN")).tag(AppLanguage.chinese)
                    Text(tr("英文", "EN")).tag(AppLanguage.english)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.small)
                .frame(width: 110)
            }

            pickerRow(title: tr("刷新频率", "Refresh"), subtitle: tr("后台扫描周期", "Background scan interval")) {
                Picker("", selection: $settings.refreshInterval) {
                    ForEach(RefreshIntervalOption.allCases) { option in
                        Text(option.label(language: settings.appLanguage)).tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 92)
            }

            pickerRow(title: tr("计数方式", "Count Mode"), subtitle: tr("菜单栏 : N 的统计规则", "Rule for menu-bar : N")) {
                Picker("", selection: $settings.countMode) {
                    Text(tr("实例", "Inst")).tag(PortCountMode.portAndPID)
                    Text(tr("端口", "Port")).tag(PortCountMode.portOnly)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.small)
                .frame(width: 114)
            }

            pickerRow(title: tr("健康重试", "Health Retries"), subtitle: tr("改端口后最多检测次数", "Max retries after port change")) {
                Picker("", selection: $settings.healthCheckMaxAttempts) {
                    ForEach(HealthCheckAttemptsOption.allCases) { option in
                        Text(option.label(language: settings.appLanguage)).tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 92)
            }

            pickerRow(title: tr("检测间隔", "Probe Interval"), subtitle: tr("每次检测前等待时长", "Wait time between probes")) {
                Picker("", selection: $settings.healthCheckProbeInterval) {
                    ForEach(HealthCheckIntervalOption.allCases) { option in
                        Text(option.label(language: settings.appLanguage)).tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 92)
            }
        }
    }

    private var safetyCard: some View {
        settingsCard(
            title: tr("安全与通知", "Safety & Notifications"),
            subtitle: tr("默认安全优先，可按需开启高级操作", "Safe by default, advanced actions are opt-in"),
            icon: "shield.lefthalf.filled.badge.checkmark",
            tone: .mint
        ) {
            toggleRow(
                title: tr("开机启动", "Launch at Login"),
                subtitle: tr("登录系统后自动启动 PortPilot", "Start PortPilot automatically after login"),
                isOn: $settings.launchAtLogin
            )
            toggleRow(
                title: tr("允许结束进程", "Enable Kill"),
                subtitle: tr("关闭后隐藏 Kill 操作", "Hide kill actions when disabled"),
                isOn: $settings.enableKill
            )
            toggleRow(
                title: tr("通知：新端口", "Notify: New Ports"),
                subtitle: tr("检测到新监听端口时提醒", "Alert when new listening ports appear"),
                isOn: $settings.notifyOnNewPort
            )
            toggleRow(
                title: tr("通知：端口冲突", "Notify: Port Conflict"),
                subtitle: tr("同端口有多个 PID 时提醒", "Alert when one port has multiple PIDs"),
                isOn: $settings.notifyOnPortConflict
            )
            toggleRow(
                title: tr("通知：扫描异常", "Notify: Scan Failure"),
                subtitle: tr("连续失败 3 次后提醒", "Alert after 3 consecutive failures"),
                isOn: $settings.notifyOnScannerFailure
            )

            if let launchError = settings.launchAtLoginError, !launchError.isEmpty {
                Text(launchError)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.red.opacity(0.82))
                    .padding(.horizontal, 2)
            }
        }
    }

    private var displayRuleCard: some View {
        settingsCard(
            title: tr("显示与规则", "Display & Rules"),
            subtitle: tr("让端口信息更易读、更贴近日常项目管理", "Make ports easier to read and manage"),
            icon: "sparkles.rectangle.stack",
            tone: .pearl
        ) {
            toggleRow(
                title: tr("显示命令行", "Show Command Line"),
                subtitle: tr("可用于区分多个同名进程（可能含敏感参数）", "Useful for same-name processes (may expose sensitive args)"),
                isOn: $settings.showCommandLine
            )
            toggleRow(
                title: tr("显示资源徽标", "Show Resource Badges"),
                subtitle: tr("在进程名旁展示 CPU / 内存占用", "Show CPU / memory badges near process names"),
                isOn: $settings.showResourceBadges
            )
            toggleRow(
                title: tr("自动建议启动项", "Auto Suggest Startup Profiles"),
                subtitle: tr("识别常见开发服务并提示保存", "Suggest saving common dev services"),
                isOn: $settings.autoSuggestProfiles
            )
            textRow(
                title: tr("忽略端口", "Ignored Ports"),
                subtitle: tr("逗号分隔，如 3000, 8080", "Comma-separated, e.g. 3000, 8080"),
                placeholder: "3000, 8080",
                text: $settings.ignoredPortsText
            )
            textRow(
                title: tr("忽略进程", "Ignored Processes"),
                subtitle: tr("逗号分隔，如 ssh, node", "Comma-separated, e.g. ssh, node"),
                placeholder: "ssh, node",
                text: $settings.ignoredProcessesText
            )
            textRow(
                title: tr("进程别名", "Process Aliases"),
                subtitle: tr("例如 node=商城后端, ssh=开发隧道", "e.g. node=Store API, ssh=Dev Tunnel"),
                placeholder: tr("node=前端服务, ssh=隧道", "node=Frontend, ssh=Tunnel"),
                text: $settings.processAliasesText
            )

            Text(
                tr(
                    "可在端口列表右键「编辑可读说明」添加用途解释，数据仅保存在本机。",
                    "Use context menu \"Edit friendly note\" in port list to add purpose hints; data is stored locally."
                )
            )
            .font(.system(size: 8, weight: .medium))
            .foregroundStyle(Color.secondary.opacity(0.86))
            .padding(.horizontal, 1)
        }
    }

    private func settingsCard<Content: View>(
        title: String,
        subtitle: String,
        icon: String,
        tone: CardTone,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.blue.opacity(0.8))
                    .frame(width: 24, height: 24)
                    .background(Color.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 10.4, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.primary.opacity(0.88))
                    Text(subtitle)
                        .font(.system(size: 8.2, weight: .medium))
                        .foregroundStyle(Color.secondary.opacity(0.88))
                }
            }

            VStack(spacing: 7) {
                content()
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(cardFill(tone))
                }
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(isDarkMode ? 0.2 : 0.72), lineWidth: 0.8)
        }
    }

    private func pickerRow<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 9.2, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.primary.opacity(0.84))
                Text(subtitle)
                    .font(.system(size: 7.8, weight: .medium))
                    .foregroundStyle(Color.secondary.opacity(0.88))
                    .lineLimit(1)
            }
            .layoutPriority(1)

            Spacer(minLength: 8)

            content()
                .controlSize(.mini)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.56), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.34), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.56), lineWidth: 0.55)
        }
    }

    private func toggleRow(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 9.2, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.primary.opacity(0.84))
                Text(subtitle)
                    .font(.system(size: 7.8, weight: .medium))
                    .foregroundStyle(Color.secondary.opacity(0.88))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.34), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.56), lineWidth: 0.55)
        }
    }

    private func textRow(
        title: String,
        subtitle: String,
        placeholder: String,
        text: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 9.2, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.primary.opacity(0.84))
            Text(subtitle)
                .font(.system(size: 7.8, weight: .medium))
                .foregroundStyle(Color.secondary.opacity(0.88))
                .lineLimit(1)

            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 8.9, weight: .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.56), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Color.white.opacity(0.56), lineWidth: 0.55)
                }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.34), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.56), lineWidth: 0.55)
        }
    }

    private func cardFill(_ tone: CardTone) -> LinearGradient {
        switch tone {
        case .sky:
            return LinearGradient(
                colors: isDarkMode
                    ? [Color.blue.opacity(0.23), Color.blue.opacity(0.12)]
                    : [Color.blue.opacity(0.18), Color.white.opacity(0.22)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .mint:
            return LinearGradient(
                colors: isDarkMode
                    ? [Color.mint.opacity(0.2), Color.mint.opacity(0.1)]
                    : [Color.mint.opacity(0.18), Color.white.opacity(0.2)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .pearl:
            return LinearGradient(
                colors: isDarkMode
                    ? [Color.white.opacity(0.1), Color.white.opacity(0.05)]
                    : [Color.white.opacity(0.4), Color.white.opacity(0.22)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(settings: SettingsStore())
            .frame(width: 420, height: 560)
    }
}
