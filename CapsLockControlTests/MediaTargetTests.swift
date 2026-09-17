import Foundation
import Testing
@testable import CapsLockControl

@Suite("미디어 명령 대상")
struct MediaTargetTests {

    private func configWithMediaShortcuts(target: MediaTarget) -> CapsLockControlConfig {
        var config = CapsLockControlConfig()
        config.setAction(.media(command: .playPause, target: target),
                         layer: .capsLock, keyIdentifier: "up")
        config.setAction(.media(command: .next, target: target),
                         layer: .capsLock, keyIdentifier: "right")
        config.setAction(.media(command: .previous, target: target),
                         layer: .capsLock, keyIdentifier: "left")
        return config
    }

    @Test("대상이 설정 파일을 왕복한다")
    func roundTrip() throws {
        var config = configWithMediaShortcuts(target: .spotify)
        config.defaults.mediaTarget = .spotify
        let decoded = try JSONDecoder().decode(
            CapsLockControlConfig.self, from: JSONEncoder().encode(config))

        #expect(decoded.defaults.mediaTarget == .spotify)
        #expect(decoded.action(layer: .capsLock, keyIdentifier: "up")
                == .media(command: .playPause, target: .spotify))
    }

    /// 이 키가 없던 시절의 설정 파일을 읽어도 동작이 바뀌면 안 된다.
    @Test("옛 설정 파일은 시스템 전체로 읽는다")
    func legacyDefaultsToSystem() throws {
        let json = """
        {"version":1,"defaults":{"whenAlreadyActive":"hide"},"layers":{
          "capsLock":{"up":{"type":"media","command":"playPause"}}}}
        """
        let config = try JSONDecoder().decode(
            CapsLockControlConfig.self, from: Data(json.utf8))

        #expect(config.defaults.mediaTarget == .system)
        #expect(config.action(layer: .capsLock, keyIdentifier: "up")
                == .media(command: .playPause, target: .system))
    }

    /// 사용자가 실제로 겪은 문제: 시스템 미디어 키라 브라우저의 유튜브가 같이 반응했다.
    @Test("걸려 있는 미디어 단축키를 한 번에 옮긴다")
    func moveAllToSpotify() {
        var config = configWithMediaShortcuts(target: .system)
        // 미디어가 아닌 단축키는 건드리면 안 된다.
        config.setAction(.application(ApplicationTarget(bundleIdentifier: "com.google.Chrome",
                                                        displayName: "Google Chrome")),
                         layer: .capsLock, keyIdentifier: "c")

        #expect(config.moveMediaShortcuts(to: .spotify) == 3)

        for key in ["up", "right", "left"] {
            guard case .media(_, let target)? =
                    config.action(layer: .capsLock, keyIdentifier: key) else {
                Issue.record("\(key) 가 미디어 동작이 아니다")
                continue
            }
            #expect(target == .spotify)
        }
        #expect(config.action(layer: .capsLock, keyIdentifier: "c")
                == .application(ApplicationTarget(bundleIdentifier: "com.google.Chrome",
                                                  displayName: "Google Chrome")))
    }

    @Test("명령 종류는 옮겨도 그대로다")
    func commandsSurviveTheMove() {
        var config = configWithMediaShortcuts(target: .system)
        config.moveMediaShortcuts(to: .spotify)

        #expect(config.action(layer: .capsLock, keyIdentifier: "up")
                == .media(command: .playPause, target: .spotify))
        #expect(config.action(layer: .capsLock, keyIdentifier: "right")
                == .media(command: .next, target: .spotify))
        #expect(config.action(layer: .capsLock, keyIdentifier: "left")
                == .media(command: .previous, target: .spotify))
    }

    @Test("이미 그 대상이면 아무것도 바꾸지 않는다")
    func noOpWhenAlreadyThere() {
        var config = configWithMediaShortcuts(target: .spotify)
        #expect(config.moveMediaShortcuts(to: .spotify) == 0)
    }

    @Test("두 레이어 모두 옮긴다")
    func bothLayers() {
        var config = CapsLockControlConfig()
        config.setAction(.media(command: .next, target: .system),
                         layer: .capsLock, keyIdentifier: "right")
        config.setAction(.media(command: .previous, target: .system),
                         layer: .rightOption, keyIdentifier: "left")

        #expect(config.moveMediaShortcuts(to: .spotify) == 2)
        #expect(config.action(layer: .rightOption, keyIdentifier: "left")
                == .media(command: .previous, target: .spotify))
    }
}
