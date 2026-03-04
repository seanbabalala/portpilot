import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        VStack(spacing: 10) {
            headerCard

            Form {
                Section {
                    Picker("刷新频率", selection: $settings.refreshInterval) {
                        ForEach(RefreshIntervalOption.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }

                    Picker("计数方式", selection: $settings.countMode) {
                        ForEach(PortCountMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Label("扫描", systemImage: "antenna.radiowaves.left.and.right")
                } footer: {
                    Text("实例计数：protocol+port+pid；端口计数：protocol+port。")
                }

                Section {
                    Toggle(isOn: $settings.showCommandLine) {
                        Label("显示命令详情（用于区分多个 SSH）", systemImage: "terminal")
                    }

                    Toggle(isOn: $settings.enableKill) {
                        Label("允许结束进程（高级）", systemImage: "bolt.trianglebadge.exclamationmark")
                    }
                } header: {
                    Label("隐私与安全", systemImage: "lock.shield")
                } footer: {
                    Text("命令详情可能包含主机名或敏感参数，默认关闭更安全。")
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(.clear)
        }
        .padding(12)
        .frame(width: 470, height: 420)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.22), lineWidth: 1)
        }
    }

    private var headerCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("PortPilot 设置")
                    .font(.system(size: 17, weight: .semibold))

                Text("更适合小白的端口监控体验")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "gearshape.2")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(7)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.16), lineWidth: 1)
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(settings: SettingsStore())
    }
}
