import Foundation

/// event tap 이 상태 기계에 넘기는 입력.
enum LayerInput: Equatable, Sendable {
    case layerDown(LayerKey)
    case layerUp(LayerKey)
    case keyDown(KeyCode, isRepeat: Bool)
    case keyUp(KeyCode)
    /// tap 재활성화·잠금 해제 등, 눌린 키 상태를 믿을 수 없게 된 순간.
    case reset
}

/// 상태 기계가 event tap 에게 돌려주는 결정.
enum LayerDecision: Equatable, Sendable {
    /// 원본 이벤트를 그대로 앱에 전달한다.
    case passThrough
    /// 원본 이벤트를 버린다.
    case swallow
    /// 원본 이벤트를 버리고, 이 (레이어, 키) 에 등록된 동작을 실행한다.
    case swallowAndPerform(layer: LayerKey, key: KeyCode)
    /// 레이어 키를 눌렀다 뗐는데 그 사이 다른 키를 하나도 안 썼다.
    /// "단독 탭" 후보다. 실제로 탭으로 칠지는 누른 시간까지 보고 밖에서 정한다.
    case swallowAndTapLayer(LayerKey)
}

/// 키보드 레이어의 순수 상태 기계.
///
/// AppKit/CoreGraphics 에 의존하지 않는다. 전부 `handle(_:isBound:)` 한 함수를
/// 통과하므로 눌림/뗌 순서가 꼬이는 시나리오를 유닛 테스트로 재현할 수 있다.
///
/// 핵심 불변식:
/// - **삼켜서 keyDown 을 없앤 키는 keyUp 도 반드시 삼킨다.**
///   레이어를 먼저 떼고 키를 나중에 떼도 앱에 짝 없는 keyUp 이 가지 않는다.
/// - 오토리핏 keyDown 은 동작을 다시 실행하지 않는다. (Chrome 이 30번 뜨면 곤란하다)
/// - 레이어 키를 두 개 겹쳐 누르면 **마지막에 누른 쪽**이 이긴다.
struct LayerStateMachine: Sendable {
    /// 등록되지 않은 키에 대한 정책.
    var unmappedKeyPolicy: UnmappedKeyPolicy

    /// 눌린 순서대로의 활성 레이어. 마지막 원소가 현재 유효한 레이어.
    private(set) var activeLayers: [LayerKey] = []

    /// keyDown 을 삼킨 키들. 짝이 되는 keyUp 도 삼키기 위해 기억한다.
    private(set) var swallowedKeys: Set<KeyCode> = []

    /// 누르고 있는 동안 다른 키를 한 번이라도 쓴 레이어.
    /// 단독 탭인지 가리는 데 쓴다.
    private(set) var layersUsedWhileHeld: Set<LayerKey> = []

    init(unmappedKeyPolicy: UnmappedKeyPolicy = CapsLockControlPolicy.unmappedKey) {
        self.unmappedKeyPolicy = unmappedKeyPolicy
    }

    /// 현재 유효한 레이어. 아무 레이어도 안 눌렸으면 nil.
    var activeLayer: LayerKey? { activeLayers.last }

    /// - Parameter isBound: 해당 (레이어, 키) 에 등록된 동작이 있는지 묻는 콜백.
    ///   상태 기계가 설정 모델을 몰라도 되도록 밖에서 주입한다.
    mutating func handle(
        _ input: LayerInput,
        isBound: (LayerKey, KeyCode) -> Bool
    ) -> LayerDecision {
        switch input {
        case .reset:
            activeLayers.removeAll()
            swallowedKeys.removeAll()
            layersUsedWhileHeld.removeAll()
            return .passThrough

        case .layerDown(let layer):
            // 오토리핏으로 같은 layerDown 이 여러 번 와도 한 번만 담는다.
            if !activeLayers.contains(layer) {
                activeLayers.append(layer)
                layersUsedWhileHeld.remove(layer)
            }
            return .swallow

        case .layerUp(let layer):
            activeLayers.removeAll { $0 == layer }
            let wasUsed = layersUsedWhileHeld.remove(layer) != nil
            return wasUsed ? .swallow : .swallowAndTapLayer(layer)

        case .keyDown(let key, let isRepeat):
            guard let layer = activeLayers.last else { return .passThrough }
            // 눌려 있는 레이어는 전부 "썼다" 로 친다. 겹쳐 누른 경우에도
            // 떼는 순간 엉뚱하게 Caps Lock 이 켜지면 안 된다.
            layersUsedWhileHeld.formUnion(activeLayers)
            let bound = isBound(layer, key)
            let shouldSwallow = bound || unmappedKeyPolicy == .swallow
            guard shouldSwallow else { return .passThrough }

            // 첫 keyDown 만 기억한다. 이미 눌려 있던 키가 레이어 도중 리핏으로
            // 들어온 경우까지 기억해 버리면 마지막 keyUp 을 삼켜서
            // 앱 쪽 키 상태가 눌린 채로 남는다.
            if !isRepeat {
                swallowedKeys.insert(key)
            }
            return (bound && !isRepeat) ? .swallowAndPerform(layer: layer, key: key) : .swallow

        case .keyUp(let key):
            return swallowedKeys.remove(key) != nil ? .swallow : .passThrough
        }
    }
}
