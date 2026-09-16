import Foundation
import Testing
@testable import CapsLockControl

private func key(_ identifier: String) -> KeyCode {
    guard let code = KeyCodeTable.keyCode(forIdentifier: identifier) else {
        fatalError("테스트 키 식별자가 잘못되었습니다: \(identifier)")
    }
    return code
}

/// Caps 레이어의 C 에만 동작이 걸려 있는 상황.
private func onlyCapsC(_ layer: LayerKey, _ code: KeyCode) -> Bool {
    layer == .capsLock && code == key("c")
}

@Suite("레이어 상태 기계")
struct LayerStateMachineTests {

    @Test("레이어가 꺼져 있으면 아무 키도 건드리지 않는다")
    func passThroughWhenIdle() {
        var machine = LayerStateMachine()
        #expect(machine.handle(.keyDown(key("c"), isRepeat: false), isBound: onlyCapsC) == .passThrough)
        #expect(machine.handle(.keyUp(key("c")), isBound: onlyCapsC) == .passThrough)
        #expect(machine.activeLayer == nil)
    }

    @Test("레이어 키 자체는 항상 삼킨다")
    func layerKeyIsSwallowed() {
        var machine = LayerStateMachine()
        #expect(machine.handle(.layerDown(.capsLock), isBound: onlyCapsC) == .swallow)
        #expect(machine.activeLayer == .capsLock)
        // 아무 키도 안 썼으므로 단독 탭 후보로 나온다. 어느 쪽이든 삼키는 건 같다.
        #expect(machine.handle(.layerUp(.capsLock), isBound: onlyCapsC)
                == .swallowAndTapLayer(.capsLock))
        #expect(machine.activeLayer == nil)
    }

    @Test("레이어를 누른 채 키를 쓰면 단독 탭이 아니다")
    func usingAKeyCancelsTheTap() {
        var machine = LayerStateMachine()
        _ = machine.handle(.layerDown(.capsLock), isBound: onlyCapsC)
        _ = machine.handle(.keyDown(key("c"), isRepeat: false), isBound: onlyCapsC)
        #expect(machine.handle(.layerUp(.capsLock), isBound: onlyCapsC) == .swallow)
    }

    @Test("등록되지 않은 키를 눌러도 단독 탭이 아니다")
    func unmappedKeyAlsoCancelsTheTap() {
        // Caps 를 누른 채 Q 를 눌렀다면 레이어를 쓴 것이다. 떼는 순간
        // 엉뚱하게 대문자 고정이 켜지면 안 된다.
        var machine = LayerStateMachine()
        _ = machine.handle(.layerDown(.capsLock), isBound: onlyCapsC)
        _ = machine.handle(.keyDown(key("q"), isRepeat: false), isBound: onlyCapsC)
        #expect(machine.handle(.layerUp(.capsLock), isBound: onlyCapsC) == .swallow)
    }

    @Test("레이어를 겹쳐 누르고 키를 쓰면 양쪽 다 단독 탭이 아니다")
    func usingAKeyCancelsTapsForEveryHeldLayer() {
        var machine = LayerStateMachine()
        _ = machine.handle(.layerDown(.capsLock), isBound: onlyCapsC)
        _ = machine.handle(.layerDown(.rightOption), isBound: onlyCapsC)
        _ = machine.handle(.keyDown(key("c"), isRepeat: false), isBound: onlyCapsC)
        #expect(machine.handle(.layerUp(.rightOption), isBound: onlyCapsC) == .swallow)
        #expect(machine.handle(.layerUp(.capsLock), isBound: onlyCapsC) == .swallow)
    }

    @Test("다시 누르면 탭 판정이 새로 시작된다")
    func tapStateResetsOnNextPress() {
        var machine = LayerStateMachine()
        _ = machine.handle(.layerDown(.capsLock), isBound: onlyCapsC)
        _ = machine.handle(.keyDown(key("c"), isRepeat: false), isBound: onlyCapsC)
        #expect(machine.handle(.layerUp(.capsLock), isBound: onlyCapsC) == .swallow)

        _ = machine.handle(.layerDown(.capsLock), isBound: onlyCapsC)
        #expect(machine.handle(.layerUp(.capsLock), isBound: onlyCapsC)
                == .swallowAndTapLayer(.capsLock))
    }

    @Test("등록된 키는 삼키고 동작을 실행한다")
    func boundKeyPerforms() {
        var machine = LayerStateMachine()
        _ = machine.handle(.layerDown(.capsLock), isBound: onlyCapsC)
        let decision = machine.handle(.keyDown(key("c"), isRepeat: false), isBound: onlyCapsC)
        #expect(decision == .swallowAndPerform(layer: .capsLock, key: key("c")))
    }

    @Test("등록되지 않은 키는 기본 정책(swallow)에서 삼켜진다")
    func unmappedKeyIsSwallowedByDefault() {
        var machine = LayerStateMachine()
        _ = machine.handle(.layerDown(.capsLock), isBound: onlyCapsC)
        #expect(machine.handle(.keyDown(key("q"), isRepeat: false), isBound: onlyCapsC) == .swallow)
    }

    @Test("정책을 passThrough 로 바꾸면 등록되지 않은 키가 그대로 나간다")
    func unmappedKeyPassesThroughUnderOtherPolicy() {
        var machine = LayerStateMachine(unmappedKeyPolicy: .passThrough)
        _ = machine.handle(.layerDown(.capsLock), isBound: onlyCapsC)
        #expect(machine.handle(.keyDown(key("q"), isRepeat: false), isBound: onlyCapsC) == .passThrough)
        // 삼키지 않았으므로 keyUp 도 그대로 나가야 한다.
        #expect(machine.handle(.keyUp(key("q")), isBound: onlyCapsC) == .passThrough)
    }

    @Test("Caps 를 먼저 떼고 키를 나중에 떼도 keyUp 이 새지 않는다")
    func keyUpAfterLayerUpIsStillSwallowed() {
        var machine = LayerStateMachine()
        _ = machine.handle(.layerDown(.capsLock), isBound: onlyCapsC)
        _ = machine.handle(.keyDown(key("c"), isRepeat: false), isBound: onlyCapsC)
        _ = machine.handle(.layerUp(.capsLock), isBound: onlyCapsC)
        #expect(machine.handle(.keyUp(key("c")), isBound: onlyCapsC) == .swallow)
        // 한 번 처리한 뒤에는 기록이 남지 않는다.
        #expect(machine.swallowedKeys.isEmpty)
    }

    @Test("오토리핏은 동작을 다시 실행하지 않는다")
    func autorepeatDoesNotRefire() {
        var machine = LayerStateMachine()
        _ = machine.handle(.layerDown(.capsLock), isBound: onlyCapsC)
        #expect(machine.handle(.keyDown(key("c"), isRepeat: false), isBound: onlyCapsC)
                == .swallowAndPerform(layer: .capsLock, key: key("c")))
        for _ in 0..<5 {
            #expect(machine.handle(.keyDown(key("c"), isRepeat: true), isBound: onlyCapsC) == .swallow)
        }
    }

    @Test("이미 눌려 있던 키의 리핏이 레이어 도중 들어와도 마지막 keyUp 은 앱에 전달된다")
    func repeatDuringLayerDoesNotStealKeyUp() {
        var machine = LayerStateMachine()
        // 사용자가 Q 를 누른 채로 타이핑 중.
        #expect(machine.handle(.keyDown(key("q"), isRepeat: false), isBound: onlyCapsC) == .passThrough)
        // 그 상태에서 Caps 를 누른다.
        _ = machine.handle(.layerDown(.capsLock), isBound: onlyCapsC)
        #expect(machine.handle(.keyDown(key("q"), isRepeat: true), isBound: onlyCapsC) == .swallow)
        // Q 를 떼면 앱은 짝이 맞는 keyUp 을 받아야 한다.
        #expect(machine.handle(.keyUp(key("q")), isBound: onlyCapsC) == .passThrough)
    }

    @Test("레이어 두 개를 겹쳐 누르면 마지막에 누른 쪽이 이긴다")
    func lastLayerWins() {
        var machine = LayerStateMachine()
        _ = machine.handle(.layerDown(.capsLock), isBound: onlyCapsC)
        _ = machine.handle(.layerDown(.rightOption), isBound: onlyCapsC)
        #expect(machine.activeLayer == .rightOption)
        // rightOption 레이어에는 C 가 없으므로 실행되지 않는다.
        #expect(machine.handle(.keyDown(key("c"), isRepeat: false), isBound: onlyCapsC) == .swallow)
        // rightOption 을 떼면 caps 가 다시 유효해진다.
        _ = machine.handle(.layerUp(.rightOption), isBound: onlyCapsC)
        #expect(machine.activeLayer == .capsLock)
        #expect(machine.handle(.keyDown(key("c"), isRepeat: false), isBound: onlyCapsC)
                == .swallowAndPerform(layer: .capsLock, key: key("c")))
    }

    @Test("레이어 키 오토리핏은 상태를 중복으로 쌓지 않는다")
    func layerDownIsIdempotent() {
        var machine = LayerStateMachine()
        for _ in 0..<3 { _ = machine.handle(.layerDown(.capsLock), isBound: onlyCapsC) }
        #expect(machine.activeLayers == [.capsLock])
        _ = machine.handle(.layerUp(.capsLock), isBound: onlyCapsC)
        #expect(machine.activeLayers.isEmpty)
    }

    @Test("reset 은 눌린 키와 레이어를 모두 잊는다")
    func resetClearsEverything() {
        var machine = LayerStateMachine()
        _ = machine.handle(.layerDown(.capsLock), isBound: onlyCapsC)
        _ = machine.handle(.keyDown(key("c"), isRepeat: false), isBound: onlyCapsC)
        _ = machine.handle(.reset, isBound: onlyCapsC)
        #expect(machine.activeLayers.isEmpty)
        #expect(machine.swallowedKeys.isEmpty)
        #expect(machine.layersUsedWhileHeld.isEmpty)
        // 초기화 뒤 들어온 keyUp 은 앱으로 나간다.
        #expect(machine.handle(.keyUp(key("c")), isBound: onlyCapsC) == .passThrough)
    }

    @Test("레이어 활성화 전에 눌려 있던 키의 keyUp 은 그대로 나간다")
    func keyUpWithoutMatchingSwallowedDown() {
        var machine = LayerStateMachine()
        _ = machine.handle(.keyDown(key("c"), isRepeat: false), isBound: onlyCapsC)
        _ = machine.handle(.layerDown(.capsLock), isBound: onlyCapsC)
        #expect(machine.handle(.keyUp(key("c")), isBound: onlyCapsC) == .passThrough)
    }
}

@Suite("키 코드 표")
struct KeyCodeTableTests {

    @Test("식별자와 키코드가 서로 왕복한다")
    func roundTrip() {
        for entry in KeyCodeTable.all {
            #expect(KeyCodeTable.keyCode(forIdentifier: entry.identifier) == entry.keyCode)
            #expect(KeyCodeTable.identifier(for: entry.keyCode) == entry.identifier)
        }
    }

    @Test("식별자는 중복되지 않는다")
    func identifiersAreUnique() {
        let identifiers = KeyCodeTable.all.map(\.identifier)
        #expect(Set(identifiers).count == identifiers.count)
    }

    @Test("QWERTY 행 구성이 기대한 개수다")
    func rowShape() {
        #expect(KeyCodeTable.numberRow.count == 13)   // ` 1..0 - =
        #expect(KeyCodeTable.topRow.count == 13)      // Q..P [ ] \
        #expect(KeyCodeTable.homeRow.count == 11)     // A..L ; '
        #expect(KeyCodeTable.bottomRow.count == 10)   // Z..M , . /
        #expect(KeyCodeTable.arrowCluster.count == 4)
        #expect(KeyCodeTable.extraCluster.count == 5)
        // 에디터의 Available 개수가 이 값에서 나온다.
        #expect(KeyCodeTable.rows.flatMap { $0 }.count == 47)
        #expect(KeyCodeTable.all.count == 56)
    }

    @Test("기호 키는 이름으로 저장하고 문자로 써도 읽힌다")
    func punctuationAliases() {
        let pairs = [(",", "comma"), (".", "period"), ("/", "slash"),
                     (";", "semicolon"), ("'", "quote"), ("[", "leftBracket"),
                     ("]", "rightBracket"), ("\\", "backslash"), ("`", "grave"),
                     ("-", "minus"), ("=", "equal")]
        for (literal, canonical) in pairs {
            #expect(KeyCodeTable.keyCode(forIdentifier: literal)
                    == KeyCodeTable.keyCode(forIdentifier: canonical),
                    "\(literal) 와 \(canonical) 가 같은 키여야 한다")
            #expect(KeyCodeTable.canonicalIdentifier(literal) == canonical)
        }
        // 저장된 식별자는 항상 정식 이름이다.
        for entry in KeyCodeTable.all {
            #expect(KeyCodeTable.canonicalIdentifier(entry.identifier) == entry.identifier)
        }
        #expect(KeyCodeTable.canonicalIdentifier("esc") == "escape")
        #expect(KeyCodeTable.canonicalIdentifier("enter") == "return")
        #expect(KeyCodeTable.canonicalIdentifier("없는키") == nil)
    }

    @Test("레이어 트리거 키는 서로 다르고 일반 키와 겹치지 않는다")
    func triggerKeysAreDistinct() {
        let triggers = LayerKey.allCases.map(\.triggerKeyCode)
        #expect(Set(triggers).count == triggers.count)
        for trigger in triggers {
            #expect(KeyCodeTable.entry(for: trigger) == nil)
        }
        #expect(LayerKey.layer(forTrigger: .f19) == .capsLock)
        #expect(LayerKey.layer(forTrigger: .f20) == .rightOption)
        #expect(LayerKey.layer(forTrigger: .f18) == nil)
    }
}

@Suite("설정 모델 인코딩")
struct ShortcutActionCodingTests {

    @Test("application 동작이 왕복한다")
    func applicationRoundTrip() throws {
        let action = ShortcutAction.application(
            ApplicationTarget(bundleIdentifier: "com.google.Chrome", displayName: "Google Chrome")
        )
        let data = try JSONEncoder().encode(action)
        #expect(try JSONDecoder().decode(ShortcutAction.self, from: data) == action)
    }

    @Test("media 동작이 왕복하고 target 이 없으면 system 으로 읽힌다")
    func mediaRoundTrip() throws {
        let action = ShortcutAction.media(command: .next, target: .spotify)
        let data = try JSONEncoder().encode(action)
        #expect(try JSONDecoder().decode(ShortcutAction.self, from: data) == action)

        let legacy = Data(#"{"type":"media","command":"playPause"}"#.utf8)
        #expect(try JSONDecoder().decode(ShortcutAction.self, from: legacy)
                == .media(command: .playPause, target: .system))
    }

    @Test("모르는 타입을 만나도 던지지 않는다")
    func unknownTypeDoesNotThrow() throws {
        let data = Data(#"{"type":"quantumTeleport","destination":"mars"}"#.utf8)
        #expect(try JSONDecoder().decode(ShortcutAction.self, from: data)
                == .unsupported(rawType: "quantumTeleport"))
    }
}
