import Foundation
import Testing
@testable import CapsLockControl

@Suite("YouTube Music 탭 제어 스크립트")
struct YouTubeMusicScriptTests {

    @Test("명령마다 플레이어 바의 해당 버튼을 누른다", arguments: [
        (MediaCommand.playPause, "#play-pause-button"),
        (MediaCommand.next, ".next-button"),
        (MediaCommand.previous, ".previous-button"),
    ])
    func pressesTheMatchingButton(command: MediaCommand, selector: String) {
        let javaScript = YouTubeMusicScript.javaScript(for: command)
        #expect(javaScript.contains("querySelector('ytmusic-player-bar')"))
        #expect(javaScript.contains("bar.querySelector('\(selector)')"))
        #expect(javaScript.contains("button.click()"))
    }

    /// AppleScript 문자열 안에 그대로 들어간다. 큰따옴표나 역슬래시가 섞이면 스크립트가 깨진다.
    @Test("자바스크립트에 큰따옴표와 역슬래시가 없다",
          arguments: [MediaCommand.playPause, .next, .previous])
    func javaScriptIsSafeToEmbed(command: MediaCommand) {
        let javaScript = YouTubeMusicScript.javaScript(for: command)
        #expect(!javaScript.contains("\""))
        #expect(!javaScript.contains("\\"))
    }

    @Test("Chrome 의 YouTube Music 탭만 찾는다")
    func targetsOnlyYouTubeMusicTabs() {
        let script = YouTubeMusicScript.appleScript(for: .next)
        #expect(script.contains("tell application id \"com.google.Chrome\""))
        #expect(script.contains("starts with \"https://music.youtube.com/\""))
    }

    /// 문법이 깨지면 키를 눌러도 아무 일 없이 실패한다. 컴파일은 Chrome 에 이벤트를 보내지 않는다.
    @Test("AppleScript 가 컴파일된다",
          .enabled(if: FileManager.default.fileExists(atPath: "/Applications/Google Chrome.app"),
                   "Chrome 이 설치되어 있어야 용어를 읽을 수 있다"),
          arguments: [MediaCommand.playPause, .next, .previous])
    func appleScriptCompiles(command: MediaCommand) {
        var errorInfo: NSDictionary?
        let script = NSAppleScript(source: YouTubeMusicScript.appleScript(for: command))
        let compiled = script?.compileAndReturnError(&errorInfo) ?? false
        #expect(compiled, "\(String(describing: errorInfo))")
    }

    // MARK: - 결과 해석

    private func outcome(_ command: MediaCommand, result: String?,
                         errorNumber: Int? = nil, errorMessage: String? = nil) -> ActionOutcome {
        YouTubeMusicScript.outcome(for: command, result: result,
                                   errorNumber: errorNumber, errorMessage: errorMessage)
    }

    @Test("재생/일시정지는 누르기 전 상태로 결과를 말한다")
    func playPauseReportsTheNewState() {
        #expect(outcome(.playPause, result: "ran:ok:paused") == .succeeded("YouTube Music 재생"))
        #expect(outcome(.playPause, result: "ran:ok:playing") == .succeeded("YouTube Music 일시정지"))
        #expect(outcome(.playPause, result: "ran:ok:unknown")
                == .succeeded("YouTube Music 재생/일시정지"))
    }

    @Test("다음·이전 곡은 상태와 무관하게 버튼 이름으로 알린다")
    func nextAndPrevious() {
        #expect(outcome(.next, result: "ran:ok:playing") == .succeeded("YouTube Music 다음 곡"))
        #expect(outcome(.previous, result: "ran:ok:paused") == .succeeded("YouTube Music 이전 곡"))
    }

    @Test("탭이 없으면 실패로 알린다")
    func noTab() {
        #expect(outcome(.next, result: "no-tab")
                == .failed("Chrome 에 YouTube Music 탭이 열려 있지 않습니다."))
    }

    /// Chrome 의 오류 문장은 표시 언어를 따라가서, 번호만 보고 안내를 붙인다.
    @Test("자바스크립트 허용이 꺼져 있으면 켜는 곳을 알려 준다", arguments: [
        "js-error:12:Executing JavaScript through AppleScript is turned off.",
        "js-error:12:AppleScript를 통한 자바스크립트 실행 기능이 꺼져 있습니다.",
    ])
    func javaScriptDisabled(result: String) {
        guard case .failed(let message) = outcome(.next, result: result) else {
            Issue.record("실패로 알려야 한다")
            return
        }
        #expect(message.contains("보기 › 개발자 › Apple Events의 자바스크립트 허용"))
    }

    @Test("그 밖의 자바스크립트 오류는 Chrome 의 문장을 그대로 보인다")
    func otherJavaScriptError() {
        #expect(outcome(.next, result: "js-error:5:Invalid URL entered.")
                == .failed("YouTube Music 제어 실패: Invalid URL entered."))
    }

    @Test("자동화 권한이 없으면 시스템 설정 위치를 알려 준다")
    func notPermitted() {
        let result = outcome(.next, result: nil, errorNumber: -1743,
                             errorMessage: "Not authorized to send Apple events to Google Chrome.")
        guard case .failed(let message) = result else {
            Issue.record("실패로 알려야 한다")
            return
        }
        #expect(message.contains("자동화"))
    }

    /// 화면 구조가 바뀌었을 때 고칠 단서가 남아야 한다.
    @Test("버튼을 못 찾으면 어느 버튼인지 알려 준다")
    func missingButton() {
        guard case .failed(let message) = outcome(.next, result: "ran:no-button") else {
            Issue.record("실패로 알려야 한다")
            return
        }
        #expect(message.contains("다음 곡"))
        #expect(message.contains(".next-button"))
    }

    @Test("플레이어가 없으면 곡을 먼저 재생하라고 알린다")
    func noPlayer() {
        guard case .failed(let message) = outcome(.playPause, result: "ran:no-player") else {
            Issue.record("실패로 알려야 한다")
            return
        }
        #expect(message.contains("플레이어가 없습니다"))
    }

    @Test("모르는 응답은 성공으로 치지 않는다", arguments: ["ran:", "ran:weird", "something"])
    func unknownResponse(result: String) {
        guard case .failed = outcome(.next, result: result) else {
            Issue.record("\(result) 를 성공으로 읽었다")
            return
        }
    }
}
