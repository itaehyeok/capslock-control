import Foundation
import Testing
@testable import CapsLockControl

@Suite("설정 파일 내보내기")
struct ConfigFileTests {

    private var sample: CapsLockControlConfig {
        var config = CapsLockControlConfig()
        config.setAction(.application(ApplicationTarget(bundleIdentifier: "com.apple.Safari",
                                                        displayName: "Safari")),
                         layer: .capsLock, keyIdentifier: "s")
        config.defaults.layerTapTimeoutMilliseconds = 300
        return config
    }

    @Test("내보낸 파일은 설정 파일과 같은 형식이라 그대로 다시 읽힌다")
    func exportedFileRoundTrips() throws {
        let data = try ConfigFile.encode(sample)
        let decoded = try JSONDecoder().decode(CapsLockControlConfig.self, from: data)
        #expect(decoded == sample)
    }

    @Test("파일 이름에 날짜가 붙는다")
    func suggestedNameHasDate() throws {
        var components = DateComponents()
        components.year = 2026
        components.month = 10
        components.day = 28
        components.hour = 12
        let date = try #require(Calendar.current.date(from: components))
        #expect(ConfigFile.suggestedName(for: date) == "CapsLock Control 단축키 2026-10-28.json")
    }
}
