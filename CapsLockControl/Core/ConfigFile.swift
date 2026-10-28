import Foundation

/// 설정을 파일 하나로 주고받는다. GitHub 없이 백업하거나 다른 Mac 으로 옮길 때 쓴다.
///
/// 형식은 `shortcuts.json` 과 똑같다. 내보낸 파일을 설정 폴더에 그대로 넣어도 읽힌다.
enum ConfigFile {

    /// 저장 창에 미리 채워 둘 파일 이름. 날짜가 붙어 있으면 여러 번 내보내도 구별된다.
    static func suggestedName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "CapsLock Control 단축키 \(formatter.string(from: date)).json"
    }

    static func encode(_ config: CapsLockControlConfig) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(config)
    }
}
