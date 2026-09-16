import ServiceManagement
import AppKit
import os

/// 로그인할 때 자동 실행.
///
/// Apple 이 현재 권장하는 `SMAppService` 를 쓴다.
/// `LSSharedFileList` 나 로그인 항목 헬퍼를 직접 다루는 옛 방식은 쓰지 않는다.
///
/// 주의: 등록은 **앱의 현재 위치**를 기준으로 기록된다.
/// `build/` 안에서 실행한 상태로 등록하면 그 경로가 저장되고, 나중에 앱을 옮기면
/// 로그인 시 실행이 조용히 실패한다. 그래서 `/Applications` 로 설치한 뒤 켜야 한다.
enum LaunchAtLogin {

    enum State: Equatable {
        case enabled
        case disabled
        /// 등록은 됐지만 사용자가 시스템 설정에서 승인해야 하는 상태.
        case requiresApproval
        case unavailable

        var isOn: Bool { self == .enabled }
    }

    private static let log = Logger(subsystem: "dev.itaehyeok.CapsLockControl", category: "LaunchAtLogin")

    static var state: State {
        switch SMAppService.mainApp.status {
        case .enabled: .enabled
        case .notRegistered: .disabled
        case .requiresApproval: .requiresApproval
        case .notFound: .unavailable
        @unknown default: .unavailable
        }
    }

    /// 앱이 `/Applications` 에 설치돼 있는지.
    /// 개발 빌드 경로에서 등록하면 경로가 바뀌는 순간 깨지므로 UI 에서 경고한다.
    static var isInstalledInApplications: Bool {
        Bundle.main.bundleURL.deletingLastPathComponent().path == "/Applications"
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
            log.info("로그인 항목 등록")
        } else {
            try SMAppService.mainApp.unregister()
            log.info("로그인 항목 해제")
        }
    }

    /// 시스템 설정 › 일반 › 로그인 항목. 승인이 필요할 때 안내한다.
    static func openLoginItemsSettings() {
        let path = "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
        guard let url = URL(string: path) else { return }
        NSWorkspace.shared.open(url)
    }
}
