import AppKit
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    let model = EngineModel()

    private let log = Logger(subsystem: "dev.itaehyeok.CapsLockControl", category: "AppDelegate")
    private var signalSources: [DispatchSourceSignal] = []

    /// 유닛 테스트가 이 앱을 테스트 호스트로 띄운다.
    /// 그때 엔진이 켜지면서 진짜 키보드를 건드리면 곤란하다.
    private var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !isRunningTests else {
            log.info("테스트 호스트로 실행 중이라 엔진을 켜지 않습니다.")
            return
        }
        installSignalHandlers()
        observeWorkspaceNotifications()
        model.startIfPossible()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // 반드시 여기서 HID 매핑을 원복해야 키보드가 정상으로 돌아온다.
        model.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // 상시 켜 두는 유틸리티다. 창을 닫아도 살아 있고, 종료는 메뉴바 › Quit 로 한다.
        false
    }

    /// 이미 실행 중인데 다시 실행 요청이 왔을 때(Finder 에서 더블클릭, `open -a`,
    /// 그리고 **CapsLock Control 자신을 가리키는 단축키**) 불린다.
    ///
    /// 메뉴바 전용 앱이 되면서 "앱을 앞으로 가져오기" 와 "창을 띄우기" 가
    /// 분리됐다. 이 훅이 없으면 단축키를 눌러도 아무 일도 일어나지 않는다.
    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            WindowOpener.shared.openKeyLayout()
        }
        return true
    }

    // MARK: - 절전 / 세션 변화

    private func observeWorkspaceNotifications() {
        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.didWakeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification,
            NSWorkspace.screensDidWakeNotification,
        ]
        for name in names {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.model.reapplyAfterWake()
                }
            }
        }
        // Karabiner 를 켜거나 끄면 경고 배너를 갱신한다.
        for name in [NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.model.refreshConflictingApps()
                }
            }
        }
        // 백그라운드 데몬은 앱 실행 알림을 주지 않는다. 사용자가 "왜 안 되지" 하고
        // 앱을 열어 보는 순간이 가장 확실한 갱신 시점이다.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.model.refreshConflictingApps()
            }
        }
    }

    // MARK: - 강제 종료 대비

    /// `pkill` 등으로 SIGTERM 이 오면 AppKit 의 종료 훅이 불리지 않는다.
    /// 그대로 죽으면 HID 매핑이 남아 Caps Lock 이 먹통이 되므로 직접 처리한다.
    private func installSignalHandlers() {
        for sig in [SIGTERM, SIGINT] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated {
                    self?.model.stop()
                    exit(0)
                }
            }
            source.resume()
            signalSources.append(source)
        }
    }
}
