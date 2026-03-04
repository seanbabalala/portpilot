import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        ZStack {
            backgroundLayer
            panel
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
        }
        .frame(width: 392)
    }

    private var backgroundLayer: some View {
        LinearGradient(
            colors: [
                Color(red: 0.14, green: 0.15, blue: 0.18),
                Color(red: 0.09, green: 0.10, blue: 0.12)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            RadialGradient(
                colors: [Color.blue.opacity(0.18), .clear],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 260
            )
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }

    private var panel: some View {
        VStack(spacing: 0) {
            navBar
            Divider().opacity(0.18)
            content
        }
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.11),
                    Color.white.opacity(0.06)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.black.opacity(0.3), lineWidth: 0.5)
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.45), radius: 22, y: 10)
    }

    private var navBar: some View {
        HStack {
            Button {
                NSApp.keyWindow?.close()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.12), in: Circle())
                    .overlay {
                        Circle()
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                            .allowsHitTesting(false)
                    }
            }
            .buttonStyle(.plain)

            Spacer()

            Text("Settings")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.96))

            Spacer()

            Color.clear
                .frame(width: 34, height: 34)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }

    private var content: some View {
        VStack(spacing: 0) {
            sectionHeader("SCAN")
            pickerRow(
                icon: "clock.arrow.2.circlepath",
                title: "Refresh Interval",
                trailing: AnyView(
                    Picker("", selection: $settings.refreshInterval) {
                        ForEach(RefreshIntervalOption.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .frame(width: 116)
                )
            )
            Divider().opacity(0.12)
            pickerRow(
                icon: "chart.bar.xaxis",
                title: "Count Mode",
                trailing: AnyView(
                    Picker("", selection: $settings.countMode) {
                        Text("By Instance").tag(PortCountMode.portAndPID)
                        Text("By Port").tag(PortCountMode.portOnly)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 192)
                )
            )

            Divider().opacity(0.2)
            sectionHeader("DISPLAY")
            toggleRow(
                icon: "terminal",
                title: "Show Command Details",
                subtitle: "用于区分多个 SSH 进程",
                isOn: $settings.showCommandLine
            )

            Divider().opacity(0.2)
            sectionHeader("SAFETY")
            toggleRow(
                icon: "bolt.trianglebadge.exclamationmark",
                title: "Allow Process Kill",
                subtitle: "关闭后禁用结束进程操作",
                isOn: $settings.enableKill
            )

            Divider().opacity(0.2)
            Text("Main window 的 Allow Process Kill 与此同步。")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.58))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
    }

    private func sectionHeader(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .kerning(2.2)
            .foregroundStyle(Color.white.opacity(0.56))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 6)
    }

    private func pickerRow(
        icon: String,
        title: String,
        trailing: AnyView
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(red: 0.42, green: 0.63, blue: 1.0))
                .frame(width: 18)

            Text(title)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.9))

            Spacer(minLength: 0)
            trailing
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func toggleRow(
        icon: String,
        title: String,
        subtitle: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(red: 0.42, green: 0.63, blue: 1.0))
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.9))
                Text(subtitle)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.58))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            Spacer(minLength: 0)

            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(settings: SettingsStore())
            .frame(width: 392)
    }
}
