import AppKit

/// "직전에 앞에 있던 앱"을 기억한다.
///
/// `AlreadyActiveBehavior.switchToPrevious` 전용. 스스로(CapsLockControl)는 기록에서 빼고,
/// 종료된 앱도 잊는다.
///
/// 이 객체는 앱이 사는 동안 계속 살아 있다(ActionExecutor 가 소유).
/// 그래서 관찰자 해제용 deinit 을 두지 않는다. nonisolated deinit 에서
/// MainActor 상태를 건드리는 쪽이 오히려 위험하다.
@MainActor
final class FrontmostAppTracker {

    private(set) var currentBundleIdentifier: String?
    private(set) var previousBundleIdentifier: String?

    private let ownBundleIdentifier = Bundle.main.bundleIdentifier

    init() {
        currentBundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let center = NSWorkspace.shared.notificationCenter

        center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] notification in
            // Notification 은 Sendable 이 아니다. MainActor 로 넘기기 전에
            // 필요한 값(문자열)만 꺼낸다.
            let bundleIdentifier = Self.bundleIdentifier(from: notification)
            MainActor.assumeIsolated {
                self?.recordActivation(of: bundleIdentifier)
            }
        }

        center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] notification in
            let bundleIdentifier = Self.bundleIdentifier(from: notification)
            MainActor.assumeIsolated {
                self?.forget(bundleIdentifier)
            }
        }
    }

    private nonisolated static func bundleIdentifier(from notification: Notification) -> String? {
        let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        return app?.bundleIdentifier
    }

    private func recordActivation(of bundleIdentifier: String?) {
        guard let bundleIdentifier else { return }
        // 설정 창을 열었다 닫았을 때 "직전 앱"이 CapsLock Control 이 되면 안 된다.
        guard bundleIdentifier != ownBundleIdentifier else { return }
        guard bundleIdentifier != currentBundleIdentifier else { return }
        previousBundleIdentifier = currentBundleIdentifier
        currentBundleIdentifier = bundleIdentifier
    }

    private func forget(_ bundleIdentifier: String?) {
        guard let bundleIdentifier else { return }
        if previousBundleIdentifier == bundleIdentifier { previousBundleIdentifier = nil }
        if currentBundleIdentifier == bundleIdentifier { currentBundleIdentifier = nil }
    }

    /// CapsLock Control 을 제외하고 마지막으로 앞에 있던 앱.
    ///
    /// 우리 자신은 기록하지 않으므로 `currentBundleIdentifier` 가 곧 그 값이다.
    /// CapsLockControl 창을 숨길 때 포커스를 돌려줄 곳으로 쓴다.
    func lastApplicationBeforeSelf() -> NSRunningApplication? {
        guard let identifier = currentBundleIdentifier else { return nil }
        return NSWorkspace.shared.runningApplications
            .first { $0.bundleIdentifier == identifier }
    }

    /// 되돌아갈 앱. 없거나 이미 종료됐으면 nil.
    func previousRunningApplication(excluding bundleIdentifier: String) -> NSRunningApplication? {
        guard let previous = previousBundleIdentifier, previous != bundleIdentifier else { return nil }
        return NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == previous }
    }
}
