import Foundation

struct PortListener: Identifiable, Hashable, Sendable {
    let processName: String
    let pid: Int
    let port: Int
    let user: String?
    let protocolName: String
    let commandLine: String?

    var id: String {
        "\(protocolName.lowercased())-\(port)-\(pid)"
    }

    func withCommandLine(_ commandLine: String?) -> PortListener {
        PortListener(
            processName: processName,
            pid: pid,
            port: port,
            user: user,
            protocolName: protocolName,
            commandLine: commandLine
        )
    }
}
