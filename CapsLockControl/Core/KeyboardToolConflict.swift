import Foundation

/// 키보드를 함께 만지는 다른 도구 하나.
///
/// 두 도구가 같은 키를 가로채면 이 앱의 단축키가 아예 안 먹는다. 그래서 알려는 준다.
/// 다만 **끄거나 지우지는 않는다** — 그건 사용자가 직접 할 일이다.
struct KeyboardToolConflict: Equatable, Identifiable, Sendable {
    /// 사용자에게 보여줄 이름.
    let name: String
    /// 지금 실제로 키를 가로채는가. false 면 흔적만 남은 상태라 경고가 아니라 안내다.
    let isIntercepting: Bool
    /// 어떻게 치우는지 한 줄 안내.
    let hint: String

    var id: String { name }
}

/// 프로세스 목록만 보고 겹치는 키보드 도구를 찾아낸다.
enum KeyboardToolDetector {

    /// `ps -Ao comm=` 출력(소문자)에서 키보드 도구를 골라낸다.
    ///
    /// 순수 함수라 실제 프로세스 없이도 검증할 수 있다. 감지가 틀리면 사용자는
    /// 단축키가 왜 안 먹는지 알 길이 없으므로 여기는 테스트로 묶어 둔다.
    static func tools(in processList: String) -> [KeyboardToolConflict] {
        var found: [KeyboardToolConflict] = []

        // Karabiner: 구성요소 중 하나라도 돌면 같은 키를 두 도구가 잡는다.
        // 이름 하나에 걸지 않는다 — 버전마다 도는 프로세스가 다르다.
        let karabinerRunning = [
            "karabiner_grabber",
            "karabiner_console_user_server",
            "karabiner_observer",
            "karabiner_session_monitor",
            "karabiner-elements",
            "karabiner-menu",
            "karabiner-virtualhiddevice-daemon",
        ]
        if karabinerRunning.contains(where: processList.contains) {
            found.append(KeyboardToolConflict(
                name: "Karabiner-Elements",
                isIntercepting: true,
                hint: "메뉴바 아이콘을 닫아도 백그라운드 데몬은 계속 키를 가로챕니다. "
                    + "Karabiner 설정에서 프로필을 빈 것으로 바꾸거나 앱을 완전히 제거해 주세요."))
        } else if processList.contains("karabiner-driverkit-virtualhiddevice") {
            // 드라이버 확장만 남은 상태. 키를 가로채지는 않으므로 경고가 아니라 안내다.
            found.append(KeyboardToolConflict(
                name: "Karabiner 드라이버 확장",
                isIntercepting: false,
                hint: "드라이버만 남아 있고 키를 가로채지는 않습니다. 지금 동작에는 문제가 없습니다. "
                    + "완전히 지우려면 시스템 설정 › 일반 › 로그인 항목 및 확장 프로그램 › 드라이버 확장에서 끄세요."))
        }

        let others: [(needle: String, name: String)] = [
            ("hammerspoon", "Hammerspoon"),
            ("keyboard maestro engine", "Keyboard Maestro Engine"),
            ("bettertouchtool", "BetterTouchTool"),
        ]
        for tool in others where processList.contains(tool.needle) {
            found.append(KeyboardToolConflict(
                name: tool.name,
                isIntercepting: true,
                hint: "같은 키에 단축키가 걸려 있으면 동작이 겹칩니다. 해당 앱에서 그 키를 비워 주세요."))
        }
        return found
    }
}
