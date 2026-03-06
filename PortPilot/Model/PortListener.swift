import Foundation

struct PortListener: Identifiable, Hashable, Sendable {
    let processName: String
    let pid: Int
    let port: Int
    let user: String?
    let protocolName: String
    let commandLine: String?
    let ppid: Int?
    let parentProcessName: String?
    let launchSource: String?
    let cpuUsagePercent: Double?
    let memoryFootprintMB: Int?

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
            commandLine: commandLine,
            ppid: ppid,
            parentProcessName: parentProcessName,
            launchSource: launchSource,
            cpuUsagePercent: cpuUsagePercent,
            memoryFootprintMB: memoryFootprintMB
        )
    }

    func withProcessName(_ processName: String) -> PortListener {
        PortListener(
            processName: processName,
            pid: pid,
            port: port,
            user: user,
            protocolName: protocolName,
            commandLine: commandLine,
            ppid: ppid,
            parentProcessName: parentProcessName,
            launchSource: launchSource,
            cpuUsagePercent: cpuUsagePercent,
            memoryFootprintMB: memoryFootprintMB
        )
    }

    func withMetadata(
        ppid: Int?,
        parentProcessName: String?,
        launchSource: String?
    ) -> PortListener {
        PortListener(
            processName: processName,
            pid: pid,
            port: port,
            user: user,
            protocolName: protocolName,
            commandLine: commandLine,
            ppid: ppid,
            parentProcessName: parentProcessName,
            launchSource: launchSource,
            cpuUsagePercent: cpuUsagePercent,
            memoryFootprintMB: memoryFootprintMB
        )
    }

    func withResourceUsage(
        cpuUsagePercent: Double?,
        memoryFootprintMB: Int?
    ) -> PortListener {
        PortListener(
            processName: processName,
            pid: pid,
            port: port,
            user: user,
            protocolName: protocolName,
            commandLine: commandLine,
            ppid: ppid,
            parentProcessName: parentProcessName,
            launchSource: launchSource,
            cpuUsagePercent: cpuUsagePercent,
            memoryFootprintMB: memoryFootprintMB
        )
    }
}
