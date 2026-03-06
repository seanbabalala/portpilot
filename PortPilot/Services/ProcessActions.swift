import Darwin
import Foundation

enum ProcessActionsError: LocalizedError {
    case invalidPID(Int)
    case permissionDenied(pid: Int)
    case timedOut(pid: Int, timeout: TimeInterval)
    case killFailed(pid: Int, errorCode: Int32)

    var errorDescription: String? {
        localizedDescription(language: .english)
    }

    func localizedDescription(language: AppLanguage) -> String {
        switch self {
        case .invalidPID(let pid):
            return language == .english
                ? "Invalid PID: \(pid)."
                : "无效 PID：\(pid)。"
        case .permissionDenied(let pid):
            return language == .english
                ? "Permission denied when terminating PID \(pid)."
                : "结束 PID \(pid) 时权限不足。"
        case .timedOut(let pid, let timeout):
            return language == .english
                ? "PID \(pid) did not exit within \(String(format: "%.1f", timeout))s."
                : "PID \(pid) 在 \(String(format: "%.1f", timeout)) 秒内未退出。"
        case .killFailed(let pid, let errorCode):
            let message = String(cString: strerror(errorCode))
            return language == .english
                ? "Failed to terminate PID \(pid): \(message) (errno \(errorCode))."
                : "结束 PID \(pid) 失败：\(message)（errno \(errorCode)）。"
        }
    }
}

struct ProcessActions {
    func terminate(
        pid: Int,
        gracefulTimeout: TimeInterval = 0.8,
        forceTimeout: TimeInterval = 0.8
    ) throws {
        guard pid > 0 else {
            throw ProcessActionsError.invalidPID(pid)
        }

        if hasExited(pid) {
            return
        }

        try send(signal: SIGTERM, to: pid)
        if waitUntilExit(pid: pid, timeout: gracefulTimeout) {
            return
        }

        try send(signal: SIGKILL, to: pid)
        if waitUntilExit(pid: pid, timeout: forceTimeout) {
            return
        }

        throw ProcessActionsError.timedOut(
            pid: pid,
            timeout: gracefulTimeout + forceTimeout
        )
    }

    private func send(signal: Int32, to pid: Int) throws {
        if Darwin.kill(pid_t(pid), signal) == 0 {
            return
        }

        let errorCode = errno

        switch errorCode {
        case EPERM:
            throw ProcessActionsError.permissionDenied(pid: pid)
        case ESRCH:
            return
        default:
            throw ProcessActionsError.killFailed(pid: pid, errorCode: errorCode)
        }
    }

    private func waitUntilExit(pid: Int, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if hasExited(pid) {
                return true
            }

            usleep(50_000)
        }

        return hasExited(pid)
    }

    private func hasExited(_ pid: Int) -> Bool {
        if Darwin.kill(pid_t(pid), 0) == 0 {
            return false
        }

        return errno == ESRCH
    }
}
