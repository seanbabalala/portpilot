import AppKit
import SwiftUI

@main
struct PortPilotApp: App {
    @StateObject private var settingsStore: SettingsStore
    @StateObject private var portsStore: PortsStore
    @StateObject private var portsScanner: PortsScanner
    @StateObject private var commandProfilesStore: CommandProfilesStore
    @StateObject private var knowledgeStore: PortKnowledgeStore

    init() {
        let settings = SettingsStore()
        let store = PortsStore(
            countMode: settings.countMode,
            settingsStore: settings
        )
        let scanner = PortsScanner(
            store: store,
            refreshInterval: TimeInterval(settings.refreshInterval.seconds),
            settingsStore: settings
        )
        scanner.start()
        let commands = CommandProfilesStore()
        let knowledge = PortKnowledgeStore()

        _settingsStore = StateObject(wrappedValue: settings)
        _portsStore = StateObject(wrappedValue: store)
        _portsScanner = StateObject(wrappedValue: scanner)
        _commandProfilesStore = StateObject(wrappedValue: commands)
        _knowledgeStore = StateObject(wrappedValue: knowledge)
    }

    private var menuBarTitle: String {
        portsScanner.isUnknown ? ": —" : ": \(portsStore.listeners.count)"
    }

    var body: some Scene {
        MenuBarExtra {
            PortsView(
                store: portsStore,
                settings: settingsStore,
                scanner: portsScanner,
                commands: commandProfilesStore,
                knowledge: knowledgeStore
            )
        } label: {
            HStack(spacing: 5) {
                MenuBarDualArcGlyph()
                    .frame(width: 14, height: 14)
                Text(menuBarTitle)
            }
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarDualArcGlyph: View {
    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0.08, to: 0.90)
                .stroke(
                    .primary.opacity(0.86),
                    style: StrokeStyle(lineWidth: 1.55, lineCap: .round)
                )
                .rotationEffect(.degrees(-30))

            Circle()
                .inset(by: 3)
                .trim(from: 0.22, to: 0.96)
                .stroke(
                    .primary.opacity(0.62),
                    style: StrokeStyle(lineWidth: 1.45, lineCap: .round)
                )
                .rotationEffect(.degrees(26))
        }
        .drawingGroup(opaque: false)
    }
}
