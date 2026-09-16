import Foundation
import IOKit
import IOKit.hidsystem
import os

/// Caps Lock 의 원래 기능(대문자 고정)을 켜고 끈다.
///
/// CGEvent 로 Caps Lock 키를 합성해도 소용없다. Caps Lock 토글은 HID 계층에서
/// 처리되기 때문이다 — event tap 으로 Caps Lock 을 막지 못하는 것과 같은 이유다.
/// 대신 IOKit 의 공개 API 로 상태를 직접 바꾼다
/// (`IOHIDLib.h` 의 `IOHIDSetModifierLockState`, private API 가 아니다).
enum CapsLockState {

    private static let log = Logger(subsystem: "dev.itaehyeok.CapsLockControl", category: "CapsLock")

    /// IOHIDSystem 에 붙어서 작업을 수행한다. 연결은 그때그때 열고 닫는다.
    /// 상시로 들고 있어 봐야 좋을 게 없고, 열고 닫는 비용도 크지 않다.
    private static func withConnection<T>(_ body: (io_connect_t) -> T) -> T? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                                  IOServiceMatching(kIOHIDSystemClass))
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }

        var connection: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_,
                            UInt32(kIOHIDParamConnectType), &connection) == KERN_SUCCESS else {
            return nil
        }
        defer { IOServiceClose(connection) }
        return body(connection)
    }

    static func current() -> Bool? {
        withConnection { connection in
            var state = false
            let result = IOHIDGetModifierLockState(connection, Int32(kIOHIDCapsLockState), &state)
            return result == KERN_SUCCESS ? state : nil
        } ?? nil
    }

    @discardableResult
    static func set(_ isOn: Bool) -> Bool {
        withConnection { connection in
            IOHIDSetModifierLockState(connection, Int32(kIOHIDCapsLockState), isOn) == KERN_SUCCESS
        } ?? false
    }

    /// 켜져 있으면 끄고, 꺼져 있으면 켠다.
    /// - Returns: 바뀐 뒤의 상태. 실패하면 nil.
    @discardableResult
    static func toggle() -> Bool? {
        guard let before = current() else {
            log.error("Caps Lock 상태를 읽지 못했습니다")
            return nil
        }
        guard set(!before) else {
            log.error("Caps Lock 상태를 바꾸지 못했습니다")
            return nil
        }
        return !before
    }
}
