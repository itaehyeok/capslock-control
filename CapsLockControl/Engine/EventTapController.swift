import CoreGraphics
import Foundation
import os

enum EventTapError: LocalizedError {
    case notTrusted
    case tapCreationFailed

    var errorDescription: String? {
        switch self {
        case .notTrusted:
            "손쉬운 사용 권한이 없어 키보드 이벤트를 읽을 수 없습니다."
        case .tapCreationFailed:
            "키보드 이벤트 탭을 만들지 못했습니다."
        }
    }
}

/// CGEventTap 의 수명 관리.
///
/// 콜백은 **메인 스레드가 아닌 전용 스레드**에서 돈다.
/// 메인 스레드가 잠깐이라도 막히면 탭이 타임아웃으로 꺼지면서
/// 키보드 입력이 통째로 먹통이 되기 때문이다.
/// 그래서 콜백 안에서는 상태 갱신만 하고, 실제 앱 실행 같은 일은
/// 바깥에서 MainActor 로 넘긴다.
final class EventTapController: @unchecked Sendable {

    /// 이벤트를 어떻게 할지 결정하는 콜백. nil 을 돌려주면 이벤트를 버린다.
    /// **탭 스레드에서 호출된다.**
    typealias Handler = @Sendable (CGEventType, CGEvent) -> CGEvent?

    private let log = Logger(subsystem: "dev.itaehyeok.CapsLockControl", category: "EventTap")
    private let handler: Handler
    private let onTapReEnabled: @Sendable () -> Void

    private let lock = NSLock()
    private var tapPort: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapThread: Thread?
    private var tapRunLoop: CFRunLoop?

    var isRunning: Bool { lock.withLock { tapPort != nil } }

    init(handler: @escaping Handler, onTapReEnabled: @escaping @Sendable () -> Void) {
        self.handler = handler
        self.onTapReEnabled = onTapReEnabled
    }

    deinit { stop() }

    // MARK: - 시작 / 정지

    func start() throws {
        guard !isRunning else { return }
        guard AccessibilityPermission.isTrusted else { throw EventTapError.notTrusted }

        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: eventTapCallback,
            userInfo: selfPtr
        ) else {
            throw EventTapError.tapCreationFailed
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
            CFMachPortInvalidate(port)
            throw EventTapError.tapCreationFailed
        }

        lock.withLock {
            tapPort = port
            runLoopSource = source
        }

        // 전용 스레드의 런루프에 붙인다. 여기서부터 콜백은 그 스레드에서 돈다.
        // CFMachPort/CFRunLoopSource 는 Sendable 이 아니지만, 여기서 만들어
        // 탭 스레드로 넘긴 뒤로는 그 스레드에서만 쓴다(정지 시에만 예외적으로
        // 락 아래에서 접근).
        nonisolated(unsafe) let handoffPort = port
        nonisolated(unsafe) let handoffSource = source
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [weak self] in
            guard let self else { ready.signal(); return }
            let runLoop = CFRunLoopGetCurrent()
            self.lock.withLock { self.tapRunLoop = runLoop }
            CFRunLoopAddSource(runLoop, handoffSource, .commonModes)
            CGEvent.tapEnable(tap: handoffPort, enable: true)
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "dev.itaehyeok.CapsLockControl.eventtap"
        thread.qualityOfService = .userInteractive
        lock.withLock { tapThread = thread }
        thread.start()
        ready.wait()

        log.info("이벤트 탭 시작")
    }

    func stop() {
        let (port, source, runLoop) = lock.withLock {
            let values = (tapPort, runLoopSource, tapRunLoop)
            tapPort = nil
            runLoopSource = nil
            tapRunLoop = nil
            tapThread = nil
            return values
        }
        guard let port else { return }

        CGEvent.tapEnable(tap: port, enable: false)
        if let runLoop, let source {
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
            CFRunLoopStop(runLoop)
        }
        CFMachPortInvalidate(port)
        log.info("이벤트 탭 정지")
    }

    // MARK: - 콜백

    /// 탭 스레드에서 호출된다.
    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // 타임아웃이나 사용자 입력으로 탭이 꺼지는 경우가 있다.
        // 다시 켜지 않으면 그 순간부터 앱이 조용히 죽은 것처럼 보인다.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            log.warning("이벤트 탭이 꺼졌습니다(\(type.rawValue)). 다시 켭니다.")
            if let port = lock.withLock({ tapPort }) {
                CGEvent.tapEnable(tap: port, enable: true)
            }
            // 꺼져 있는 동안의 키 뗌을 놓쳤을 수 있으니 상태를 초기화한다.
            onTapReEnabled()
            return Unmanaged.passUnretained(event)
        }

        guard let result = handler(type, event) else { return nil }
        return Unmanaged.passUnretained(result)
    }
}

private let eventTapCallback: CGEventTapCallBack = { _, type, event, refcon in
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let controller = Unmanaged<EventTapController>.fromOpaque(refcon).takeUnretainedValue()
    return controller.handle(type: type, event: event)
}
