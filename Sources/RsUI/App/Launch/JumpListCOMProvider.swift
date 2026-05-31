import Foundation
import RsHelper
import CRsUIJumpList

// Win32 COM backend (ICustomDestinationList via the CRsUIJumpList bridge) for
// the taskbar "New Window" entry, used because an unpackaged EXE can't use the
// WinRT JumpList API. The only file that imports CRsUIJumpList — a future
// WinRT-based provider can replace it and drop the C++ target without touching
// App.swift or the TaskbarNewWindowProvider protocol.
struct JumpListCOMProvider: TaskbarNewWindowProvider {
    // Win32 jump lists work for any unpackaged desktop EXE.
    var isAvailable: Bool { true }

    // Sets the process AUMID and registers one task that relaunches this EXE.
    // Failures are logged, never thrown — a missing taskbar entry must not
    // block startup.
    func register(aumid: String, title: String, argument: String) {
        let aumidStatus = rs_set_app_user_model_id(wide(aumid))
        if aumidStatus != 0 {
            log.warning("rs_set_app_user_model_id failed: HRESULT 0x\(String(aumidStatus, radix: 16))")
        }

        guard let exePath = selfExePath() else {
            log.warning("rs_get_self_exe_path failed")
            return
        }

        let status = rs_register_new_window_task(
            wide(aumid), wide(exePath), wide(argument), wide(title), wide(exePath), 0)
        if status != 0 {
            log.warning("rs_register_new_window_task failed: HRESULT 0x\(String(status, radix: 16))")
        }
    }

    private func selfExePath() -> String? {
        var buf = [UInt16](repeating: 0, count: 1024)
        let written = buf.withUnsafeMutableBufferPointer {
            rs_get_self_exe_path($0.baseAddress, Int32($0.count))
        }
        guard written > 0 else { return nil }
        return String(decoding: buf[0..<Int(written)], as: UTF16.self)
    }

    // Null-terminated wide-char array passed straight as const wchar_t* to the
    // C bridge, avoiding per-argument nested withCString.
    private func wide(_ s: String) -> [UInt16] { Array(s.utf16) + [0] }
}
