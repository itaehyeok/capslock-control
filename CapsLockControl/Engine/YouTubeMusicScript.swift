import Foundation

/// Chrome 에 열린 YouTube Music 탭을 조종하는 AppleScript 를 만들고, 그 결과를 해석한다.
///
/// 실행(NSAppleScript)은 `MediaController` 가 한다. 여기는 문자열만 다루는 순수 함수라서
/// Chrome 없이 테스트할 수 있다.
///
/// 흐름:
/// 1. Chrome 의 모든 창에서 `https://music.youtube.com/` 탭을 찾는다.
///    창마다 URL 목록을 한 번에 받는다. 탭마다 물으면 Apple Event 가 탭 수만큼 오간다.
/// 2. 찾은 탭에서 자바스크립트로 플레이어 바의 버튼을 누른다. 사람이 누른 것과 같아서
///    "이전 곡" 을 곡 중간에 누르면 곡 처음으로 가는 동작도 그대로다.
/// 3. 결과를 짧은 표식 문자열로 돌려준다. 표식의 뜻은 `outcome(for:...)` 이 풀어 준다.
///
/// 시스템 미디어 키(`.system`)와 달리 다른 유튜브 탭이 재생 중이어도 YouTube Music 탭만 받는다.
/// 대신 Chrome 의 "Apple Events의 자바스크립트 허용" 을 켜 두어야 한다. 그 설정은 프로필마다
/// 따로라서, YouTube Music 을 여는 프로필 창에서 켜야 한다.
enum YouTubeMusicScript {

    static let chromeBundleIdentifier = "com.google.Chrome"
    static let urlPrefix = "https://music.youtube.com/"

    /// Chrome 의 "Apple Events의 자바스크립트 허용" 이 꺼져 있을 때 오는 오류 번호.
    /// Chrome 소스 `error_applescript.h` 의 `kJavaScriptUnsupported`.
    /// 오류 문장은 Chrome 의 표시 언어를 따라가서 번호로 가린다.
    static let javaScriptDisabledErrorNumber = 12

    /// 자동화 권한이 없을 때 macOS 가 내는 오류 번호(`errAEEventNotPermitted`).
    static let notPermittedErrorNumber = -1743

    /// 플레이어 바(`ytmusic-player-bar`) 안의 버튼.
    static func buttonSelector(for command: MediaCommand) -> String {
        switch command {
        case .playPause: "#play-pause-button"
        case .next: ".next-button"
        case .previous: ".previous-button"
        }
    }

    /// 탭 안에서 돌 자바스크립트.
    ///
    /// AppleScript 문자열 안에 그대로 넣으므로 작은따옴표만 쓴다(큰따옴표·역슬래시 금지).
    /// 재생/일시정지는 누르기 **전** 상태를 `<video>` 에서 읽어 둔다. 버튼 제목(재생/일시중지)은
    /// 표시 언어마다 달라서 기준으로 못 쓴다.
    static func javaScript(for command: MediaCommand) -> String {
        [
            "(function () {",
            "var bar = document.querySelector('ytmusic-player-bar');",
            "if (!bar) { return 'no-player'; }",
            "var button = bar.querySelector('\(buttonSelector(for: command))');",
            "if (!button) { return 'no-button'; }",
            "var video = document.querySelector('video');",
            "var before = video ? (video.paused ? 'paused' : 'playing') : 'unknown';",
            "button.click();",
            "return 'ok:' + before;",
            "})();",
        ].joined(separator: " ")
    }

    /// Chrome 에 보낼 AppleScript.
    ///
    /// 돌려주는 표식:
    /// - `ran:<자바스크립트 결과>` — 탭을 찾아 자바스크립트를 실행했다
    /// - `js-error:<번호>:<메시지>` — 탭은 찾았지만 자바스크립트를 못 돌렸다
    /// - `no-tab` — YouTube Music 탭이 없다
    ///
    /// YouTube Music 탭이 여러 개면 처음 찾은 탭만 조종한다.
    static func appleScript(for command: MediaCommand) -> String {
        """
        tell application id "\(chromeBundleIdentifier)"
            repeat with w in windows
                set tabURLs to URL of tabs of w
                repeat with i from 1 to count of tabURLs
                    if item i of tabURLs starts with "\(urlPrefix)" then
                        try
                            set jsResult to execute tab i of w javascript "\(javaScript(for: command))"
                            if jsResult is missing value then return "ran:"
                            return "ran:" & jsResult
                        on error errorMessage number errorNumber
                            return "js-error:" & errorNumber & ":" & errorMessage
                        end try
                    end if
                end repeat
            end repeat
        end tell
        return "no-tab"
        """
    }

    /// 실행 결과를 사용자에게 보일 문장으로 바꾼다.
    ///
    /// - Parameters:
    ///   - result: 스크립트가 돌려준 표식. 스크립트 자체가 실패했으면 nil.
    ///   - errorNumber: 스크립트 자체가 실패했을 때의 오류 번호(자동화 권한 없음 등).
    ///   - errorMessage: 그때의 오류 문장.
    static func outcome(
        for command: MediaCommand,
        result: String?,
        errorNumber: Int?,
        errorMessage: String?
    ) -> ActionOutcome {
        if let errorNumber {
            if errorNumber == notPermittedErrorNumber {
                return .failed("Chrome 을 제어할 권한이 없습니다. 시스템 설정 › 개인정보 보호 및 보안 › "
                               + "자동화 에서 CapsLock Control 의 Google Chrome 을 켜 주세요.")
            }
            return .failed("YouTube Music 제어 실패: \(errorMessage ?? "오류 \(errorNumber)")")
        }
        guard let result else {
            return .failed("YouTube Music 제어 실패: Chrome 이 응답하지 않았습니다.")
        }

        if result == "no-tab" {
            // 탭을 대신 열지 않는다. 열어도 재생할 곡이 정해져 있지 않다.
            return .failed("Chrome 에 YouTube Music 탭이 열려 있지 않습니다.")
        }
        if result.hasPrefix("js-error:") {
            let parts = result.dropFirst("js-error:".count).split(separator: ":", maxSplits: 1)
            if parts.first.flatMap({ Int($0) }) == javaScriptDisabledErrorNumber {
                return .failed("Chrome 의 보기 › 개발자 › Apple Events의 자바스크립트 허용 을 켜 주세요. "
                               + "YouTube Music 을 여는 프로필 창에서 켜야 합니다.")
            }
            let message = parts.count > 1 ? String(parts[1]) : result
            return .failed("YouTube Music 제어 실패: \(message)")
        }
        guard result.hasPrefix("ran:") else {
            return .failed("YouTube Music 제어 실패: 알 수 없는 응답 \(result)")
        }

        switch result.dropFirst("ran:".count) {
        case "no-player":
            return .failed("YouTube Music 탭에 플레이어가 없습니다. 곡을 한 번 재생해 두세요.")
        case "no-button":
            // 화면 구조가 바뀌면 여기로 온다. 무엇을 찾았는지 남겨야 고칠 수 있다.
            return .failed("YouTube Music 화면에서 \(buttonName(for: command)) 버튼을 못 찾았습니다 "
                           + "(\(buttonSelector(for: command))). 화면 구조가 바뀌었을 수 있습니다.")
        case "ok:paused" where command == .playPause:
            return .succeeded("YouTube Music 재생")
        case "ok:playing" where command == .playPause:
            return .succeeded("YouTube Music 일시정지")
        case let other where other.hasPrefix("ok:"):
            return .succeeded("YouTube Music \(buttonName(for: command))")
        case let other:
            return .failed("YouTube Music 제어 실패: 알 수 없는 응답 \(other)")
        }
    }

    private static func buttonName(for command: MediaCommand) -> String {
        switch command {
        case .playPause: "재생/일시정지"
        case .next: "다음 곡"
        case .previous: "이전 곡"
        }
    }
}
