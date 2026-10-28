import AppKit

/// 설정 파일이 없을 때 처음 한 번 만들어지는 기본 설정.
///
/// **비어 있는 상태로 시작한다.** 단축키는 사람마다 쓰는 앱이 달라서 미리 채워 두면
/// 대부분 지우는 일부터 해야 한다. 키보드 그림에서 빈 키를 눌러 하나씩 지정한다.
///
/// 키보드를 바꾸는 고급 설정(fn ↔ 왼쪽 Control 스왑, Right Command → F18)도 꺼진 채로 시작한다.
/// 설정 파일에 없는 항목이 조용히 키보드를 바꿔 버리면 안 된다.
enum DefaultConfiguration {

    static func make() -> CapsLockControlConfig {
        CapsLockControlConfig(
            version: CapsLockControlConfig.currentVersion,
            defaults: CapsLockControlConfig.Defaults(),
            rightCommand: CapsLockControlConfig.RightCommandConfig(action: .disabled),
            modifiers: CapsLockControlConfig.ModifierConfig(swapFnAndLeftControl: false),
            layers: [
                LayerKey.capsLock.rawValue: [:],
            ]
        )
    }

    /// 이 Mac 에 설치되어 있는지. UI 의 Missing 표시에 쓴다.
    static func isInstalled(bundleIdentifier: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
    }
}
