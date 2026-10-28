import Foundation
import IOKit
import os

/// Caps Lock / Right Command 를 HID 레벨에서 다른 키로 바꾼다.
///
/// 왜 event tap 이 아니라 HID 리맵인가:
/// Caps Lock 의 토글과 LED 는 세션 event tap 보다 아래 계층에서 처리된다.
/// tap 에서 이벤트를 버려도 LED 는 켜지고, macOS 가 Caps Lock 에 거는 hold-delay
/// 때문에 레이어 키로 쓰기엔 반응도 느리다. Karabiner 가 가상 HID 드라이버를
/// 만드는 이유가 이것이다. 우리는 드라이버 대신 Apple 이 제공하는
/// `/usr/bin/hidutil` 의 UserKeyMapping 을 쓴다.
///
/// 성질:
/// - 영구 설정이 아니다. 재부팅/로그아웃하면 사라진다.
/// - 앱 종료 시 `remove()` 로 원복한다.
/// - 명령 실행 시점에 붙어 있던 키보드에만 적용된다 → 핫플러그 시 다시 건다.
/// - 앱이 강제 종료되면 매핑이 남는다. 복구: `hidutil property --set '{"UserKeyMapping":[]}'`
final class HIDRemapper: @unchecked Sendable {

    /// `hidutil` 의 usage 표기는 `(usage page << 32) | usage` 다.
    /// 예: Keyboard/Keypad page 는 0x07 이므로 caps lock(0x39) 은 0x700000039.
    enum HIDUsage {
        static let capsLock: UInt64 = 0x700000039
        static let leftControl: UInt64 = 0x7000000E0
        static let rightCommand: UInt64 = 0x7000000E7
        static let f18: UInt64 = 0x70000006D
        static let f19: UInt64 = 0x70000006E
        /// fn(지구본) 키는 일반 키보드 page 가 아니라
        /// Apple vendor top case page(0xFF) 에 있다.
        static let fn: UInt64 = 0xFF00000003
    }

    struct Mapping: Sendable, Hashable, Identifiable {
        let source: UInt64
        let destination: UInt64
        let label: String

        var id: UInt64 { source }
    }

    /// 레이어 키는 구조적이라 설정과 무관하게 항상 건다.
    static let layerMappings: [Mapping] = [
        Mapping(source: HIDUsage.capsLock, destination: HIDUsage.f19, label: "Caps Lock → F19"),
    ]

    static let rightCommandToF18 = Mapping(
        source: HIDUsage.rightCommand, destination: HIDUsage.f18, label: "Right Command → F18")

    /// fn 과 왼쪽 Control 맞바꾸기. 양방향이라 두 줄이 필요하다.
    static let fnControlSwap: [Mapping] = [
        Mapping(source: HIDUsage.fn, destination: HIDUsage.leftControl,
                label: "fn → Left Control"),
        Mapping(source: HIDUsage.leftControl, destination: HIDUsage.fn,
                label: "Left Control → fn"),
    ]

    /// 설정에 따라 실제로 걸 매핑 목록을 만든다.
    static func mappings(for config: CapsLockControlConfig) -> [Mapping] {
        var result = layerMappings
        if config.rightCommand.action == .f18 {
            result.append(rightCommandToF18)
        }
        if config.modifiers.swapFnAndLeftControl {
            result.append(contentsOf: fnControlSwap)
        }
        return result
    }

    static var defaultMappings: [Mapping] { layerMappings }

    private let log = Logger(subsystem: "dev.itaehyeok.CapsLockControl", category: "HIDRemapper")
    private let queue = DispatchQueue(label: "dev.itaehyeok.CapsLockControl.hid")
    private var mappings: [Mapping]

    private let stateLock = NSLock()
    private var _isApplied = false
    private var notificationPort: IONotificationPortRef?
    private var deviceIterator: io_iterator_t = 0
    private var pendingReapply: DispatchWorkItem?

    /// 매핑을 걸거나 풀 때마다 불린다. 핫플러그 재적용 실패도 여기로 온다.
    /// 그래서 UI 의 초록 체크가 실제 상태와 어긋나지 않는다.
    var onStateChange: (@Sendable (Bool, String?) -> Void)?

    var isApplied: Bool {
        stateLock.withLock { _isApplied }
    }

    var currentMappings: [Mapping] {
        stateLock.withLock { mappings }
    }

    init(mappings: [Mapping] = HIDRemapper.defaultMappings) {
        self.mappings = mappings
    }

    /// 설정이 바뀌어 매핑 구성이 달라졌을 때. 이미 걸려 있으면 즉시 다시 건다.
    func updateMappings(_ newMappings: [Mapping]) {
        let changed: Bool = stateLock.withLock {
            guard mappings != newMappings else { return false }
            mappings = newMappings
            return true
        }
        guard changed else { return }
        if isApplied { apply() } else { onStateChange?(false, nil) }
    }

    // MARK: - 적용 / 해제

    /// 매핑을 건다. 이미 걸려 있어도 다시 걸어도 안전하다(멱등).
    @discardableResult
    func apply() -> Bool {
        let current = currentMappings
        let entries = current.map { ["HIDKeyboardModifierMappingSrc": $0.source,
                                     "HIDKeyboardModifierMappingDst": $0.destination] }
        let ok = runHidutil(userKeyMapping: entries)
        stateLock.withLock { _isApplied = ok }
        if ok {
            log.info("HID 매핑 적용: \(current.map(\.label).joined(separator: ", "))")
            onStateChange?(true, nil)
        } else {
            log.error("HID 매핑 적용 실패")
            onStateChange?(false, "hidutil 로 키 매핑을 걸지 못했습니다.")
        }
        return ok
    }

    /// 매핑을 전부 해제해 키보드를 원래대로 되돌린다.
    @discardableResult
    func remove() -> Bool {
        let ok = runHidutil(userKeyMapping: [])
        if ok { stateLock.withLock { _isApplied = false } }
        log.info("HID 매핑 해제: \(ok ? "성공" : "실패")")
        onStateChange?(isApplied, ok ? nil : "hidutil 로 키 매핑을 해제하지 못했습니다.")
        return ok
    }

    private func runHidutil(userKeyMapping: [[String: UInt64]]) -> Bool {
        let payload: [String: Any] = ["UserKeyMapping": userKeyMapping]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else {
            return false
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        process.arguments = ["property", "--set", json]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            log.error("hidutil 실행 실패: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - 키보드 핫플러그 감시

    /// 새 HID 기기가 붙으면 매핑을 다시 건다.
    /// hidutil 은 "지금 붙어 있는" 기기에만 적용되기 때문에 이게 없으면
    /// 외장 키보드를 꽂는 순간 Caps Lock 이 조용히 원래대로 돌아간다.
    func startWatchingForNewDevices() {
        queue.async { [weak self] in
            guard let self, self.notificationPort == nil else { return }
            guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
            IONotificationPortSetDispatchQueue(port, self.queue)
            self.notificationPort = port

            let matching = IOServiceMatching(kIOHIDDeviceKey)
            let selfPtr = Unmanaged.passUnretained(self).toOpaque()
            let result = IOServiceAddMatchingNotification(
                port, kIOMatchedNotification, matching, hidDeviceMatchedCallback,
                selfPtr, &self.deviceIterator
            )
            guard result == KERN_SUCCESS else {
                self.log.error("HID 기기 감시 등록 실패: \(result)")
                IONotificationPortDestroy(port)
                self.notificationPort = nil
                return
            }
            // 등록 직후엔 이미 붙어 있는 기기들이 iterator 에 담겨 온다.
            // 반드시 비워야 다음 알림이 온다.
            self.drainIterator(scheduleReapply: false)
        }
    }

    func stopWatchingForNewDevices() {
        queue.async { [weak self] in
            guard let self else { return }
            self.pendingReapply?.cancel()
            self.pendingReapply = nil
            if self.deviceIterator != 0 {
                IOObjectRelease(self.deviceIterator)
                self.deviceIterator = 0
            }
            if let port = self.notificationPort {
                IONotificationPortDestroy(port)
                self.notificationPort = nil
            }
        }
    }

    /// C 콜백에서 호출된다. 이미 `queue` 위다.
    fileprivate func deviceMatched() {
        drainIterator(scheduleReapply: true)
    }

    private func drainIterator(scheduleReapply: Bool) {
        guard deviceIterator != 0 else { return }
        var found = false
        while case let service = IOIteratorNext(deviceIterator), service != 0 {
            IOObjectRelease(service)
            found = true
        }
        guard scheduleReapply, found, isApplied else { return }
        // 여러 기기가 한꺼번에 붙는 경우가 흔해서 한 번으로 합친다.
        // 기기가 준비되기 전에 걸면 무시되므로 약간 늦춘다.
        pendingReapply?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.apply() }
        pendingReapply = work
        queue.asyncAfter(deadline: .now() + 0.7, execute: work)
    }

    /// 잠자기에서 깨어난 뒤 등, 밖에서 다시 걸어야 할 때.
    func reapplyIfNeeded() {
        queue.async { [weak self] in
            guard let self, self.isApplied else { return }
            self.apply()
        }
    }
}

private func hidDeviceMatchedCallback(_ refcon: UnsafeMutableRawPointer?, _ iterator: io_iterator_t) {
    guard let refcon else { return }
    Unmanaged<HIDRemapper>.fromOpaque(refcon).takeUnretainedValue().deviceMatched()
}
