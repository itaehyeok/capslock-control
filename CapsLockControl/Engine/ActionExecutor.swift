import AppKit
import os

/// 동작 실행 결과. UI 로그에 그대로 찍힌다.
enum ActionOutcome: Sendable, Equatable {
    case succeeded(String)
    case failed(String)
}

/// 단축키에 걸린 동작을 실제로 수행한다.
/// 항상 MainActor 에서 돈다. 이벤트 탭 스레드에서 직접 부르지 않는다.
@MainActor
final class ActionExecutor {

    /// 같은 앱에 대한 연타를 무시하는 간격.
    ///
    /// 앱 활성화가 비동기라서, 아주 빠르게 두 번 누르면 두 번째 판정 시점에
    /// 아직 frontmost 가 안 바뀌어 있을 수 있다. 그러면 토글이 타이밍에 따라
    /// 먹기도 하고 안 먹기도 한다. 그 애매함을 없애려고 "방금 내가 건드린 앱"에
    /// 대한 재입력은 무시한다.
    private static let repeatSuppressionInterval: TimeInterval = 0.25

    /// 키별 설정이 없을 때 쓰는 전역 기본값.
    var defaultWhenAlreadyActive: AlreadyActiveBehavior = .hide

    private let log = Logger(subsystem: "dev.itaehyeok.CapsLockControl", category: "Action")
    private let report: @MainActor (ActionOutcome) -> Void
    private let tracker = FrontmostAppTracker()
    private var lastTouched: (bundleIdentifier: String, at: Date)?

    init(report: @escaping @MainActor (ActionOutcome) -> Void) {
        self.report = report
    }

    func perform(_ action: ShortcutAction) {
        switch action {
        case .application(let target):
            performApplication(target)
        case .media(let command, let target):
            MediaController.perform(command, target: target, report: report)
        case .keyStroke(let stroke):
            report(KeyStrokeSender.send(stroke))
        case .unsupported(let rawType):
            report(.failed("이 버전이 모르는 동작 타입입니다: \(rawType)"))
        }
    }

    // MARK: - 앱

    private func performApplication(_ target: ApplicationTarget) {
        let name = displayName(for: target)

        if let last = lastTouched,
           last.bundleIdentifier == target.bundleIdentifier,
           Date().timeIntervalSince(last.at) < Self.repeatSuppressionInterval {
            log.debug("연타 억제: \(name, privacy: .public)")
            return
        }
        lastTouched = (target.bundleIdentifier, Date())

        let isFrontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            == target.bundleIdentifier
        guard isFrontmost else {
            activate(bundleIdentifier: target.bundleIdentifier, name: name)
            return
        }

        switch target.whenAlreadyActive ?? defaultWhenAlreadyActive {
        case .nothing:
            report(.succeeded("\(name) (이미 맨 앞)"))
        case .hide:
            hide(bundleIdentifier: target.bundleIdentifier, name: name)
        case .switchToPrevious:
            switchToPrevious(from: target.bundleIdentifier, name: name)
        }
    }

    /// 실행 중이면 앞으로 가져오고, 아니면 실행한다.
    ///
    /// 두 경우를 나누지 않고 `openApplication(at:)` 하나로 처리한다.
    /// LaunchServices 가 알아서 기존 인스턴스를 활성화해 주고,
    /// 백그라운드 앱이 남의 앱을 앞으로 끌어오는 문제도 대신 처리해 준다.
    private func activate(bundleIdentifier: String, name: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            report(.failed("\(name): 설치되어 있지 않습니다 (\(bundleIdentifier))"))
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            Task { @MainActor [report = self.report] in
                if let error {
                    report(.failed("\(name) 실행 실패: \(error.localizedDescription)"))
                } else {
                    report(.succeeded(name))
                }
            }
        }
    }

    /// ⌘H 와 같다. 숨기면 macOS 가 알아서 다음 앱을 앞으로 가져온다.
    private func hide(bundleIdentifier: String, name: String) {
        // 자기 자신은 남의 앱처럼 숨길 수 없다.
        guard bundleIdentifier != Bundle.main.bundleIdentifier else {
            hideSelf(name: name)
            return
        }
        guard let app = runningApplication(bundleIdentifier) else {
            report(.failed("\(name) 이(가) 실행 중이 아닙니다."))
            return
        }
        // hide() 가 false 를 돌려주는데 실제로는 숨겨지는 앱이 있다(Tot 등).
        // 반환값만 믿고 실패라고 알리면 사용자를 헷갈리게 한다. 잠깐 뒤 실제
        // 상태를 보고 판단한다.
        let reportedSuccess = app.hide()
        Task { @MainActor [report] in
            try? await Task.sleep(for: .milliseconds(120))
            if reportedSuccess || app.isHidden || !app.isActive {
                report(.succeeded("\(name) 숨김"))
            } else {
                // 풀스크린 앱 등은 정말로 숨겨지지 않는다.
                report(.failed("\(name) 을(를) 숨길 수 없습니다."))
            }
        }
    }

    /// CapsLock Control 자신을 숨긴다.
    ///
    /// `NSRunningApplication.hide()` 로는 안 된다. 자기 프로세스에는 잘 듣지 않고,
    /// 특히 메뉴바 전용 앱(`LSUIElement` = accessory)에서는 조용히 실패한다.
    /// 그래서 창을 직접 내리고 포커스를 되돌려 준다.
    private func hideSelf(name: String) {
        for window in NSApp.windows
        where window.isVisible && window.styleMask.contains(.titled) {
            window.orderOut(nil)
        }
        // 창만 내리면 포커스가 어디로 갈지 불확실하다. 직전에 쓰던 앱으로 돌려준다.
        if let previous = tracker.lastApplicationBeforeSelf() {
            NSApp.yieldActivation(to: previous)
            previous.activate()
            report(.succeeded("\(name) 숨김 → \(previous.localizedName ?? "직전 앱")"))
        } else {
            NSApp.hide(nil)
            report(.succeeded("\(name) 숨김"))
        }
    }

    /// 이 앱 직전에 앞에 있던 앱으로 되돌아간다. 기록이 없으면 숨기기로 폴백한다.
    private func switchToPrevious(from bundleIdentifier: String, name: String) {
        guard bundleIdentifier != Bundle.main.bundleIdentifier else {
            hideSelf(name: name)
            return
        }
        guard let previous = tracker.previousRunningApplication(excluding: bundleIdentifier),
              let previousID = previous.bundleIdentifier else {
            log.debug("직전 앱 기록이 없어 숨기기로 대체합니다.")
            hide(bundleIdentifier: bundleIdentifier, name: name)
            return
        }
        let previousName = previous.localizedName ?? previousID
        activate(bundleIdentifier: previousID, name: previousName)
    }

    private func runningApplication(_ bundleIdentifier: String) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications
            .first { $0.bundleIdentifier == bundleIdentifier }
    }

    private func displayName(for target: ApplicationTarget) -> String {
        target.displayName.isEmpty ? target.bundleIdentifier : target.displayName
    }
}
