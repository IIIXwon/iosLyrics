import Foundation

/// 로그 한 줄의 수준·분류·문구 (작업 035). 시스템 로그 호출은 ExperimentController에 있음
nonisolated enum LogLine {
    enum Level: Equatable { case notice, warning, error }
    enum Category: String, Equatable { case sdk, location, card, app }

    /// 맨 앞 글자로 판단: ❌·⛔ → error, ⚠️ → warning, ⚡로 시작하고 "실패" 포함 → warning, 그 밖은 notice (중간의 ❌는 보지 않음)
    static func level(of message: String) -> Level {
        switch message.unicodeScalars.first?.value {
        case 0x274C, 0x26D4: return .error   // ❌, ⛔ (뒤의 U+FE0F는 보지 않음)
        case 0x26A0: return .warning         // ⚠
        case 0x26A1: return message.contains("실패") ? .warning : .notice   // ⚡ SDK 줄 중 실패
        default: return .notice
        }
    }

    /// 맨 앞 글자로 판단: ⚡ → sdk, 📍 → location, 🪪 → card, 그 밖은 app
    static func category(of message: String) -> Category {
        switch message.unicodeScalars.first?.value {
        case 0x26A1: return .sdk        // ⚡
        case 0x1F4CD: return .location  // 📍
        case 0x1FAAA: return .card      // 🪪
        default: return .app
        }
    }

    /// 초 → "m:ss". 음수는 0
    static func time(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// 곡 줄: "\(prefix)🎵 곡: 가수 - 제목 (위치 / 길이)"
    static func song(prefix: String, artist: String, title: String,
                     position: TimeInterval, duration: TimeInterval) -> String {
        "\(prefix)🎵 곡: \(artist) - \(title) (\(time(position)) / \(time(duration)))"
    }

    /// 위치 수신 0회 줄의 뒷부분
    static func noFixNote(authorization: String) -> String {
        "저전력 설정에서는 정상일 수 있어요 (권한 \(authorization))"
    }
}

/// 같은 줄이 연속으로 나오면 한 번만 남기기 (작업 035)
nonisolated struct RepeatFilter: Equatable {
    private var last: String?

    init() {}

    /// 직전 키와 다르면 true
    mutating func shouldLog(_ key: String) -> Bool {
        if last == key { return false }
        last = key
        return true
    }

    mutating func reset() { last = nil }
}
