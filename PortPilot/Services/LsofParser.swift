import Foundation

struct LsofParser {
    func parse(stdout: String) -> [PortListener] {
        stdout
            .split(whereSeparator: \.isNewline)
            .compactMap { parseLine(String($0)) }
    }

    private func parseLine(_ rawLine: String) -> PortListener? {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return nil }

        if line.uppercased().hasPrefix("COMMAND") {
            return nil
        }

        let tokens = line
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)

        guard tokens.count >= 2 else { return nil }
        guard let pid = Int(tokens[1]) else { return nil }

        let processName = tokens[0]
        let user = tokens.count >= 3 ? tokens[2] : nil
        let protocolName = tokens.first(where: { $0.uppercased().hasPrefix("TCP") })?.uppercased() ?? "TCP"

        guard let nameField = extractNameField(from: tokens) else { return nil }
        guard let port = extractPort(fromNameField: nameField) else { return nil }

        return PortListener(
            processName: processName,
            pid: pid,
            port: port,
            user: user,
            protocolName: protocolName,
            commandLine: nil,
            ppid: nil,
            parentProcessName: nil,
            launchSource: nil,
            cpuUsagePercent: nil,
            memoryFootprintMB: nil
        )
    }

    private func extractNameField(from tokens: [String]) -> String? {
        if let listenIndex = tokens.firstIndex(of: "(LISTEN)"), listenIndex > 0 {
            return tokens[listenIndex - 1]
        }

        if let protocolIndex = tokens.firstIndex(where: { $0.uppercased().hasPrefix("TCP") }),
           protocolIndex + 1 < tokens.count {
            return tokens[protocolIndex + 1]
        }

        return tokens.last
    }

    private func extractPort(fromNameField nameField: String) -> Int? {
        let localEndpoint = nameField.components(separatedBy: "->").first ?? nameField
        guard let suffix = localEndpoint.split(separator: ":").last else { return nil }
        guard !suffix.isEmpty else { return nil }
        guard suffix.allSatisfy(\.isNumber) else { return nil }
        return Int(suffix)
    }
}
