import Darwin
import Foundation

enum ProcessActionsError: LocalizedError {
    case invalidPID(Int)
    case permissionDenied(pid: Int)
    case noSuchProcess(pid: Int)
    case killFailed(pid: Int, errorCode: Int32)

    var errorDescription: String? {
        switch self {
        case .invalidPID(let pid):
            return "Invalid PID: \(pid)."
        case .permissionDenied(let pid):
            return "Permission denied when terminating PID \(pid)."
        case .noSuchProcess(let pid):
            return "Process PID \(pid) no longer exists."
        case .killFailed(let pid, let errorCode):
            let message = String(cString: strerror(errorCode))
            return "Failed to terminate PID \(pid): \(message) (errno \(errorCode))."
        }
    }
}

struct ProcessActions {
    func terminate(pid: Int) throws {
        guard pid > 0 else {
            throw ProcessActionsError.invalidPID(pid)
        }

        if Darwin.kill(pid_t(pid), SIGTERM) == 0 {
            return
        }

        let errorCode = errno

        switch errorCode {
        case EPERM:
            throw ProcessActionsError.permissionDenied(pid: pid)
        case ESRCH:
            throw ProcessActionsError.noSuchProcess(pid: pid)
        default:
            throw ProcessActionsError.killFailed(pid: pid, errorCode: errorCode)
        }
    }
}
