import Darwin
import Foundation

struct LsofResult {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

enum LsofRunnerError: Error {
    case launchFailed(underlying: Error)
    case timedOut(seconds: TimeInterval)
}

final class LsofRunner {
    private let candidateExecutablePaths = [
        "/usr/sbin/lsof",
        "/usr/bin/lsof"
    ]
    private let arguments = ["-nP", "-iTCP", "-sTCP:LISTEN"]

    func run(timeout: TimeInterval = 2) async throws -> LsofResult {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = resolveExecutableURL()
        process.arguments = arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw LsofRunnerError.launchFailed(underlying: error)
        }

        let completed = try await waitForExit(process, timeout: timeout)
        if !completed {
            terminate(process)
            throw LsofRunnerError.timedOut(seconds: timeout)
        }

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        return LsofResult(
            stdout: String(decoding: stdoutData, as: UTF8.self),
            stderr: String(decoding: stderrData, as: UTF8.self),
            exitCode: process.terminationStatus
        )
    }

    private func waitForExit(_ process: Process, timeout: TimeInterval) async throws -> Bool {
        let deadline = Date().addingTimeInterval(timeout)

        while process.isRunning {
            if Date() >= deadline {
                return false
            }

            try await Task.sleep(nanoseconds: 50_000_000)
        }

        return true
    }

    private func terminate(_ process: Process) {
        guard process.isRunning else { return }

        process.terminate()

        let spinCount = 10
        for _ in 0..<spinCount where process.isRunning {
            usleep(50_000)
        }

        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }

        process.waitUntilExit()
    }

    private func resolveExecutableURL() -> URL {
        let fileManager = FileManager.default

        for path in candidateExecutablePaths where fileManager.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }

        return URL(fileURLWithPath: candidateExecutablePaths[0])
    }
}
