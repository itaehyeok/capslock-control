import AppKit
import IOKit.hidsystem
import os

/// 미디어 재생 제어.
///
/// 세 가지 경로가 있다.
///
/// **`.system` (기본)** — 하드웨어 미디어 키와 똑같은 시스템 이벤트를 만들어 보낸다.
/// macOS 가 "지금 재생 중인 앱"에게 전달하므로 Spotify 가 재생 중이면 Spotify 가 받는다.
/// 권한이 따로 필요 없고, Apple Music 으로 갈아타도 그대로 동작한다.
/// 쓰는 상수는 IOKit 공개 헤더(`ev_keymap.h`)의 `NX_KEYTYPE_*` 이다.
///
/// **`.spotify`** — Spotify 에만 AppleScript 로 직접 명령한다. 무엇이 재생 중이든
/// 항상 Spotify 를 제어하지만, 처음 한 번 자동화 권한을 물어본다.
///
/// **`.youTubeMusic`** — Chrome 의 YouTube Music 탭에서 AppleScript 로 자바스크립트를
/// 실행해 플레이어 버튼을 누른다. 스크립트 내용은 `YouTubeMusicScript` 에 있다.
enum MediaController {

    private static let log = Logger(subsystem: "dev.itaehyeok.CapsLockControl", category: "Media")
    private static let spotifyBundleIdentifier = "com.spotify.client"
    /// AppleScript 는 응답을 기다릴 수 있어서 메인 스레드에서 실행하지 않는다.
    private static let scriptQueue = DispatchQueue(label: "dev.itaehyeok.CapsLockControl.applescript")

    @MainActor
    static func perform(
        _ command: MediaCommand,
        target: MediaTarget,
        report: @escaping @MainActor (ActionOutcome) -> Void
    ) {
        switch target {
        case .system:
            postSystemMediaKey(for: command)
            report(.succeeded(label(for: command)))
        case .spotify:
            controlSpotify(command, report: report)
        case .youTubeMusic:
            controlYouTubeMusic(command, report: report)
        }
    }

    private static func label(for command: MediaCommand) -> String {
        switch command {
        case .playPause: "Play/Pause"
        case .next: "Next track"
        case .previous: "Previous track"
        }
    }

    // MARK: - 시스템 미디어 키

    private static func keyType(for command: MediaCommand) -> Int32 {
        switch command {
        case .playPause: Int32(NX_KEYTYPE_PLAY)
        case .next: Int32(NX_KEYTYPE_NEXT)
        case .previous: Int32(NX_KEYTYPE_PREVIOUS)
        }
    }

    @MainActor
    private static func postSystemMediaKey(for command: MediaCommand) {
        let type = keyType(for: command)
        // 누름과 뗌을 짝으로 보내야 한다. 하나만 보내면 눌린 채로 남는 앱이 있다.
        postAuxKey(type: type, isDown: true)
        postAuxKey(type: type, isDown: false)
    }

    @MainActor
    private static func postAuxKey(type: Int32, isDown: Bool) {
        // NX_SYSDEFINED 의 보조 버튼 이벤트 형식:
        // data1 상위 16비트 = 키 종류, 하위에 누름/뗌 상태가 들어간다.
        let state: Int32 = isDown ? 0x0A : 0x0B
        let data1 = Int((type << 16) | (state << 8))
        guard let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state) << 8),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: Int16(NX_SUBTYPE_AUX_CONTROL_BUTTONS),
            data1: data1,
            data2: -1
        ), let cgEvent = event.cgEvent else {
            log.error("미디어 키 이벤트를 만들지 못했습니다.")
            return
        }
        cgEvent.post(tap: CGEventTapLocation.cghidEventTap)
    }

    // MARK: - Spotify 직접 제어

    @MainActor
    private static func controlSpotify(
        _ command: MediaCommand,
        report: @escaping @MainActor (ActionOutcome) -> Void
    ) {
        let isRunning = NSWorkspace.shared.runningApplications
            .contains { $0.bundleIdentifier == spotifyBundleIdentifier }
        guard isRunning else {
            // 명령만 보내면 Spotify 가 실행되면서 재생까지 시작한다. 그건 원하는 동작이 아니다.
            report(.failed("Spotify 가 실행 중이 아닙니다."))
            return
        }

        let verb: String
        switch command {
        case .playPause: verb = "playpause"
        case .next: verb = "next track"
        case .previous: verb = "previous track"
        }
        let source = "tell application id \"\(spotifyBundleIdentifier)\" to \(verb)"

        scriptQueue.async {
            var errorInfo: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&errorInfo)
            let message = errorInfo?[NSAppleScript.errorMessage] as? String
            Task { @MainActor in
                if let message {
                    report(.failed("Spotify 제어 실패: \(message)"))
                } else {
                    report(.succeeded("Spotify \(label(for: command))"))
                }
            }
        }
    }

    // MARK: - YouTube Music (Chrome 탭) 직접 제어

    @MainActor
    private static func controlYouTubeMusic(
        _ command: MediaCommand,
        report: @escaping @MainActor (ActionOutcome) -> Void
    ) {
        let isRunning = NSWorkspace.shared.runningApplications
            .contains { $0.bundleIdentifier == YouTubeMusicScript.chromeBundleIdentifier }
        guard isRunning else {
            // 명령만 보내면 Chrome 이 새로 뜬다. 그래도 YouTube Music 탭은 없으니 의미가 없다.
            report(.failed("Chrome 이 실행 중이 아닙니다."))
            return
        }

        let source = YouTubeMusicScript.appleScript(for: command)
        scriptQueue.async {
            var errorInfo: NSDictionary?
            let result = NSAppleScript(source: source)?.executeAndReturnError(&errorInfo)
            let outcome = YouTubeMusicScript.outcome(
                for: command,
                result: errorInfo == nil ? result?.stringValue : nil,
                errorNumber: errorInfo?[NSAppleScript.errorNumber] as? Int,
                errorMessage: errorInfo?[NSAppleScript.errorMessage] as? String
            )
            // 화면 구조에 기대는 경로라 결과를 시스템 로그에도 남긴다.
            // 깨지면 `log show` 로 무엇을 못 찾았는지 바로 볼 수 있다.
            switch outcome {
            case .succeeded(let message):
                log.notice("\(message, privacy: .public)")
            case .failed(let message):
                log.error("\(message, privacy: .public)")
            }
            Task { @MainActor in
                report(outcome)
            }
        }
    }
}
