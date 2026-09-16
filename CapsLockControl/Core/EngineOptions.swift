import Foundation

/// 설정에서 뽑아낸, 엔진의 동작 방식.
/// 바인딩 표와 달리 키 목록이 아니라 "어떻게 처리할지" 를 담는다.
struct EngineOptions: Sendable, Equatable {
    var unmappedKeyPolicy: UnmappedKeyPolicy
    /// Caps Lock 을 단독으로 짧게 눌렀다 떼면 원래 기능(대문자 고정)을 토글한다.
    var capsLockTapTogglesCapsLock: Bool
    /// 단독 탭으로 칠 시간 한도.
    var layerTapTimeout: TimeInterval

    init(unmappedKeyPolicy: UnmappedKeyPolicy = CapsLockControlPolicy.unmappedKey,
         capsLockTapTogglesCapsLock: Bool = true,
         layerTapTimeout: TimeInterval = 0.25) {
        self.unmappedKeyPolicy = unmappedKeyPolicy
        self.capsLockTapTogglesCapsLock = capsLockTapTogglesCapsLock
        self.layerTapTimeout = layerTapTimeout
    }

    init(config: CapsLockControlConfig) {
        self.init(
            unmappedKeyPolicy: config.defaults.unmappedKeyPolicy,
            capsLockTapTogglesCapsLock: config.defaults.capsLockTapTogglesCapsLock,
            layerTapTimeout: Double(config.defaults.layerTapTimeoutMilliseconds) / 1000
        )
    }
}
