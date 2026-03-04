import AppKit
import SwiftUI

@main
struct PortPilotApp: App {
    @StateObject private var settingsStore: SettingsStore
    @StateObject private var portsStore: PortsStore
    @StateObject private var portsScanner: PortsScanner

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

        _settingsStore = StateObject(wrappedValue: settings)
        _portsStore = StateObject(wrappedValue: store)
        _portsScanner = StateObject(wrappedValue: scanner)
    }

    private var menuBarTitle: String {
        portsScanner.isUnknown ? ": —" : ": \(portsStore.listeners.count)"
    }

    var body: some Scene {
        MenuBarExtra(menuBarTitle, systemImage: "dot.radiowaves.left.and.right") {
            PortsView(store: portsStore, settings: settingsStore, scanner: portsScanner)
        }
        .menuBarExtraStyle(.window)
    }
}
