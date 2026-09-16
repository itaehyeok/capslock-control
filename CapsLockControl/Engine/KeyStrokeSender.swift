import CoreGraphics
import Foundation
import os

/// 다른 앱의 전역 단축키를 부르기 위해 키 조합을 대신 눌러 준다.
///
/// 왜 이게 통하는가: `RegisterEventHotKey`(Carbon) 로 등록된 단축키는
/// WindowServer 가 이벤트 스트림을 보고 판정한다. 그래서 우리가 만든 이벤트도
/// 수정자 플래그가 맞으면 하드웨어로 누른 것과 똑같이 처리된다.
///
/// 주의: 우리가 만든 이벤트는 우리 이벤트 탭에도 다시 들어온다.
/// 표시를 남기지 않으면 Caps+A → 조합 발생 → 탭이 다시 잡음 → 무한 루프가 된다.
/// 그래서 모든 합성 이벤트에 `syntheticMarker` 를 박고, 탭은 그 표시를 보면
/// 손대지 않고 흘려보낸다.
enum KeyStrokeSender {

    /// 'KYLR'. 우리 이벤트임을 알아보는 표시.
    static let syntheticMarker: Int64 = 0x4B594C52

    private static let log = Logger(subsystem: "dev.itaehyeok.CapsLockControl", category: "KeyStroke")

    static func send(_ stroke: KeyStroke) -> ActionOutcome {
        guard let keyCode = KeyCodeTable.keyCode(forIdentifier: stroke.keyIdentifier) else {
            return .failed("알 수 없는 키입니다: \(stroke.keyIdentifier)")
        }
        let flags = cgEventFlags(for: stroke.modifiers)
        // 하드웨어 수정자 상태가 섞이지 않도록 별도 소스를 매번 만든다.
        // Caps 를 누른 채로 발생시켜도 우리가 지정한 플래그만 실린다.
        // CGEventSource 는 Sendable 이 아니라서 전역으로 들고 있지 않는다.
        let eventSource = CGEventSource(stateID: .privateState)

        for isKeyDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: eventSource,
                                      virtualKey: keyCode.rawValue,
                                      keyDown: isKeyDown) else {
                log.error("키 이벤트를 만들지 못했습니다: \(stroke.comboString, privacy: .public)")
                return .failed("\(stroke.comboString) 를 만들지 못했습니다.")
            }
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
            event.post(tap: .cghidEventTap)
        }
        return .succeeded(stroke.displayName)
    }

    static func cgEventFlags(for modifiers: [KeyStrokeModifier]) -> CGEventFlags {
        var flags: CGEventFlags = []
        for modifier in modifiers {
            switch modifier {
            case .control: flags.insert(.maskControl)
            case .option: flags.insert(.maskAlternate)
            case .shift: flags.insert(.maskShift)
            case .command: flags.insert(.maskCommand)
            }
        }
        return flags
    }
}
