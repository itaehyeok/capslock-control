import AppKit
import ApplicationServices

/// 손쉬운 사용(Accessibility) 권한 확인 및 안내.
enum AccessibilityPermission {

    /// 현재 프로세스가 신뢰됨(=이벤트 탭을 만들 수 있음) 상태인지.
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// `kAXTrustedCheckOptionPrompt` 는 SDK 에서 전역 var 로 선언돼 있어
    /// Swift 6 동시성 검사에 걸린다. 값이 바뀌지 않는 문서화된 키라 문자열로 쓴다.
    private static let promptOptionKey = "AXTrustedCheckOptionPrompt"

    /// macOS 표준 권한 요청 시트를 띄운다. 이미 허용된 상태면 아무 일도 없다.
    @discardableResult
    static func promptIfNeeded() -> Bool {
        AXIsProcessTrustedWithOptions([promptOptionKey: true] as CFDictionary)
    }

    /// 시스템 설정 > 개인정보 보호 및 보안 > 손쉬운 사용 을 연다.
    static func openSystemSettings() {
        let path = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        guard let url = URL(string: path) else { return }
        NSWorkspace.shared.open(url)
    }
}
