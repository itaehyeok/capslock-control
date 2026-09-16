import CoreGraphics
import Foundation
import os

/// 엔진이 바깥(=UI)에 알려 주는 사건.
enum EngineEvent: Sendable {
    case layerChanged(LayerKey?)
    case performed(layer: LayerKey, key: KeyCode, action: ShortcutAction)
    case swallowedUnmapped(layer: LayerKey, key: KeyCode)
    case stateReset(reason: String)
    case hidMappingStateChanged(isApplied: Bool, errorMessage: String?)
    /// 레이어 키를 아무 것과도 조합하지 않고 짧게 눌렀다 뗐다.
    case layerTapped(LayerKey)
}

/// 이벤트 탭 · 상태 기계 · 동작 실행을 연결하는 조립부.
///
/// 스레드 규칙:
/// - `process(...)` 는 이벤트 탭 스레드에서 불린다. 락 안에서 상태만 갱신하고 바로 반환한다.
/// - 실제 동작 실행과 UI 갱신은 `Task { @MainActor }` 로 넘긴다.
final class KeyboardEngine: @unchecked Sendable {

    /// 레이어가 켜져 있어도 절대 삼키지 않는 키.
    /// F18 은 Right Command 가 HID 레벨에서 바뀐 결과라서 늘 macOS 로 흘려보내야
    /// 한/영 전환이 동작한다.
    private static let alwaysPassThrough: Set<KeyCode> = [.f18]

    private let log = Logger(subsystem: "dev.itaehyeok.CapsLockControl", category: "Engine")
    private let lock = NSLock()
    private var stateMachine = LayerStateMachine()
    private var bindings = BindingTable()
    private var options = EngineOptions()
    /// 레이어 키를 누른 시각. 단독 탭인지 가리는 데 쓴다.
    private var layerPressedAt: [LayerKey: TimeInterval] = [:]

    private let hidRemapper: HIDRemapper
    private var tapController: EventTapController?
    private let observer: @Sendable (EngineEvent) -> Void
    private let executeAction: @Sendable (LayerKey, KeyCode, ShortcutAction) -> Void

    private(set) var isRunning = false

    var activeLayer: LayerKey? { lock.withLock { stateMachine.activeLayer } }
    var isHIDMappingApplied: Bool { hidRemapper.isApplied }
    var hidMappings: [HIDRemapper.Mapping] { hidRemapper.currentMappings }
    var bindingCount: Int { lock.withLock { bindings.count } }

    init(
        hidRemapper: HIDRemapper = HIDRemapper(),
        observer: @escaping @Sendable (EngineEvent) -> Void,
        executeAction: @escaping @Sendable (LayerKey, KeyCode, ShortcutAction) -> Void
    ) {
        self.hidRemapper = hidRemapper
        self.observer = observer
        self.executeAction = executeAction
        hidRemapper.onStateChange = { isApplied, errorMessage in
            observer(.hidMappingStateChanged(isApplied: isApplied, errorMessage: errorMessage))
        }
    }

    // MARK: - 설정

    /// 설정이 바뀔 때마다 호출한다. 엔진이 켜져 있어도 안전하다.
    func updateConfiguration(
        bindings newBindings: BindingTable,
        hidMappings: [HIDRemapper.Mapping],
        options newOptions: EngineOptions
    ) {
        lock.withLock {
            bindings = newBindings
            options = newOptions
            stateMachine.unmappedKeyPolicy = newOptions.unmappedKeyPolicy
        }
        hidRemapper.updateMappings(hidMappings)
    }

    // MARK: - 수명

    func start() throws {
        guard !isRunning else { return }

        let controller = EventTapController(
            handler: { [weak self] type, event in
                guard let self else { return event }
                return self.process(type: type, event: event)
            },
            onTapReEnabled: { [weak self] in
                self?.resetState(reason: "이벤트 탭 재활성화")
            }
        )
        // 권한이 없으면 여기서 던진다. HID 매핑은 아직 걸지 않았으므로 원복할 것도 없다.
        try controller.start()
        tapController = controller

        hidRemapper.apply()
        hidRemapper.startWatchingForNewDevices()
        isRunning = true
        log.info("엔진 시작")
    }

    func stop() {
        guard isRunning else { return }
        hidRemapper.stopWatchingForNewDevices()
        hidRemapper.remove()
        tapController?.stop()
        tapController = nil
        resetState(reason: "엔진 정지")
        isRunning = false
        log.info("엔진 정지")
    }

    /// 잠자기에서 깨어난 뒤 등, 매핑이 날아갔을 수 있을 때 다시 건다.
    func reapplyHIDMapping() {
        guard isRunning else { return }
        hidRemapper.reapplyIfNeeded()
        resetState(reason: "절전 복귀")
    }

    private func resetState(reason: String) {
        let previousLayer: LayerKey? = lock.withLock {
            let previous = stateMachine.activeLayer
            _ = stateMachine.handle(.reset, isBound: { _, _ in false })
            layerPressedAt.removeAll()
            return previous
        }
        observer(.stateReset(reason: reason))
        if previousLayer != nil { observer(.layerChanged(nil)) }
    }

    // MARK: - 이벤트 처리 (탭 스레드)

    private func process(type: CGEventType, event: CGEvent) -> CGEvent? {
        guard type == .keyDown || type == .keyUp else { return event }

        // CapsLock Control 이 직접 만든 이벤트는 다시 해석하지 않는다.
        // 이게 없으면 keyStroke 동작이 자기 자신을 무한히 다시 부른다.
        guard event.getIntegerValueField(.eventSourceUserData)
                != KeyStrokeSender.syntheticMarker else { return event }

        let keyCode = KeyCode(CGKeyCode(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode)))
        guard !Self.alwaysPassThrough.contains(keyCode) else { return event }

        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        let input: LayerInput
        if let layer = LayerKey.layer(forTrigger: keyCode) {
            input = (type == .keyDown) ? .layerDown(layer) : .layerUp(layer)
        } else {
            input = (type == .keyDown) ? .keyDown(keyCode, isRepeat: isRepeat) : .keyUp(keyCode)
        }

        let now = Date.timeIntervalSinceReferenceDate
        let (decision, layerBefore, layerAfter, action, tappedLayer) = lock.withLock {
            let before = stateMachine.activeLayer
            let table = bindings
            if case .layerDown(let layer) = input, layerPressedAt[layer] == nil {
                layerPressedAt[layer] = now
            }
            let decision = stateMachine.handle(input) { layer, key in
                table.contains(layer: layer, key: key)
            }
            var resolved: ShortcutAction?
            if case .swallowAndPerform(let layer, let key) = decision {
                resolved = table.action(for: layer, key: key)
            }
            // 짧게 눌렀다 뗀 것만 탭으로 친다. 오래 누르고 있다 뗀 건
            // "레이어를 켰다가 그냥 놓은" 경우라 아무 일도 하면 안 된다.
            var tapped: LayerKey?
            if case .swallowAndTapLayer(let layer) = decision {
                let pressedAt = layerPressedAt.removeValue(forKey: layer)
                if options.capsLockTapTogglesCapsLock, layer == .capsLock,
                   let pressedAt, now - pressedAt <= options.layerTapTimeout {
                    tapped = layer
                }
            } else if case .layerUp(let layer) = input {
                layerPressedAt.removeValue(forKey: layer)
            }
            return (decision, before, stateMachine.activeLayer, resolved, tapped)
        }

        if let tappedLayer {
            observer(.layerTapped(tappedLayer))
        }

        if layerBefore != layerAfter {
            observer(.layerChanged(layerAfter))
        }

        switch decision {
        case .passThrough:
            return event
        case .swallowAndTapLayer:
            return nil
        case .swallow:
            // 레이어 키 자신(F19/F20)이 삼켜진 것은 로그에 남기지 않는다.
            if type == .keyDown, LayerKey.layer(forTrigger: keyCode) == nil, let layer = layerAfter {
                observer(.swallowedUnmapped(layer: layer, key: keyCode))
            }
            return nil
        case .swallowAndPerform(let layer, let key):
            if let action {
                observer(.performed(layer: layer, key: key, action: action))
                executeAction(layer, key, action)
            }
            return nil
        }
    }
}
