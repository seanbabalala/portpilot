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
        MenuBarExtra(menuBarTitle, systemImage: "dot.radiowaves.left.and.right") {
            PortsView(
                store: portsStore,
                settings: settingsStore,
                scanner: portsScanner,
                commands: commandProfilesStore,
                knowledge: knowledgeStore
            )
        }
        .menuBarExtraStyle(.window)
    }
}
