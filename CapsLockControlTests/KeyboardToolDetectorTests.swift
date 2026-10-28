import Foundation
import Testing
@testable import CapsLockControl

@Suite("겹치는 키보드 도구 감지")
struct KeyboardToolDetectorTests {

    /// `ps -Ao comm=` 는 실행 파일 경로를 그대로 내놓는다. 감지는 소문자 입력을 받는다.
    private func processList(_ lines: [String]) -> String {
        lines.joined(separator: "\n").lowercased()
    }

    @Test("아무것도 없으면 조용하다")
    func noTools() {
        let list = processList([
            "/usr/libexec/runningboardd",
            "/applications/capslockcontrol.app/contents/macos/capslockcontrol",
        ])
        #expect(KeyboardToolDetector.tools(in: list).isEmpty)
    }

    @Test("grabber 가 돌면 가로채는 중으로 본다")
    func grabberIntercepts() {
        let list = processList([
            "/library/application support/org.pqrs/karabiner-elements/bin/karabiner_grabber",
        ])
        let tools = KeyboardToolDetector.tools(in: list)
        #expect(tools.count == 1)
        #expect(tools.first?.name == "Karabiner-Elements")
        #expect(tools.first?.isIntercepting == true)
    }

    /// 사용자가 실제로 겪은 상황: GUI 없이 데몬만 돌아 단축키가 통째로 죽었다.
    @Test("GUI 없이 데몬만 돌아도 잡아낸다")
    func daemonWithoutGUI() {
        for daemon in ["karabiner_console_user_server",
                       "karabiner_observer",
                       "karabiner_session_monitor",
                       "Karabiner-VirtualHIDDevice-Daemon",
                       "Karabiner-Menu"] {
            let list = processList(["/some/path/\(daemon)"])
            let tools = KeyboardToolDetector.tools(in: list)
            #expect(tools.first?.isIntercepting == true, "\(daemon) 를 놓쳤다")
        }
    }

    /// 드라이버 확장만 남은 상태는 경고가 아니다. 여기서 노란 배너를 띄우면
    /// 진짜 경고가 묻힌다.
    @Test("드라이버 확장만 남으면 안내로만 표시한다")
    func driverLeftoverIsNotAWarning() {
        let list = processList([
            "/library/systemextensions/0318b04b/org.pqrs.karabiner-driverkit-virtualhiddevice.dext/org.pqrs.karabiner-driverkit-virtualhiddevice",
        ])
        let tools = KeyboardToolDetector.tools(in: list)
        #expect(tools.count == 1)
        #expect(tools.first?.isIntercepting == false)
        #expect(tools.first?.settingsLink == .driverExtensions)
    }

    /// 주소가 URL 로 안 바뀌면 버튼을 눌러도 아무 일도 없다.
    @Test("드라이버 확장 설정 주소는 URL 로 바뀐다")
    func driverExtensionsLinkIsValidURL() {
        let url = URL(string: KeyboardToolConflict.SettingsLink.driverExtensions.address)
        #expect(url?.scheme == "x-apple.systempreferences")
    }

    @Test("데몬과 드라이버가 같이 돌면 경고 하나로 합친다")
    func daemonWinsOverDriver() {
        let list = processList([
            "/library/systemextensions/x/org.pqrs.karabiner-driverkit-virtualhiddevice",
            "/library/application support/org.pqrs/karabiner-elements/bin/karabiner_grabber",
        ])
        let tools = KeyboardToolDetector.tools(in: list)
        #expect(tools.count == 1)
        #expect(tools.first?.isIntercepting == true)
    }

    @Test("Karabiner 외의 도구도 찾는다")
    func otherTools() {
        let list = processList([
            "/applications/hammerspoon.app/contents/macos/hammerspoon",
            "/applications/keyboard maestro.app/contents/macos/keyboard maestro engine",
        ])
        let names = KeyboardToolDetector.tools(in: list).map(\.name)
        #expect(names.contains("Hammerspoon"))
        #expect(names.contains("Keyboard Maestro Engine"))
    }

    @Test("ps 가 실패해 빈 문자열이 와도 죽지 않는다")
    func emptyInput() {
        #expect(KeyboardToolDetector.tools(in: "").isEmpty)
    }
}
