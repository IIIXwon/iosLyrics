// 순수 로직 — 잠금화면 카드를 언제·어떻게 갱신할지 판단 (작업 034, ExperimentController에서 옮김)
// 앱 타깃 전용 타입(ContentState)에 기대지 않도록 비교용 값(CardSnapshot)을 따로 둠
import Foundation

/// 카드에 보이는 내용 중 갱신 여부를 가르는 값 (ContentState의 일부)
nonisolated struct CardSnapshot: Equatable {
    var previous: String
    var current: String
    var next: String
    var isPlaying: Bool
    var countdown: Int
}

/// 카드를 갱신하는 이유 (로그 문구 포함)
nonisolated enum CardUpdateReason: Equatable {
    case first, trackChanged, textChanged, resumed, paused, lineChanged
    case lyrics(LyricsKind), quotaNotice, idleNotice

    var text: String {
        switch self {
        case .first: return "처음"
        case .trackChanged: return "곡 변경"
        case .textChanged: return "표시 내용 변경"
        case .resumed: return "재생"
        case .paused: return "일시정지"
        case .lineChanged: return "가사 줄 변경"
        case .quotaNotice: return "한도 차단 안내"
        case .idleNotice: return "위치 추적 끄기 직전 안내"
        case .lyrics(let kind):
            switch kind {
            case .synced: return "가사 도착"
            case .plain: return "싱크 가사 없음 (일반 가사만)"
            case .instrumental: return "연주곡"
            case .none: return "가사 없음"
            }
        }
    }
}

nonisolated enum CardPlan {
    /// 카드를 갱신해야 하는 이유. 필요 없으면 nil
    static func reason(old: CardSnapshot?, new: CardSnapshot, trackChanged: Bool) -> CardUpdateReason? {
        guard let old else { return .first }
        if trackChanged { return .trackChanged }
        if textChanged(old, new) { return .textChanged }
        if old.isPlaying != new.isPlaying { return new.isPlaying ? .resumed : .paused }
        // 숫자만 바뀐 건 줄 변경 예약과 같은 이유로 보내 로그를 늘리지 않음 (작업 020)
        if old.countdown != new.countdown { return .lineChanged }
        // 카드에 시간·진행 막대가 없으므로 시간 보정·일시정지 위치 이동은 보이지 않는 변화 → 갱신하지 않음 (작업 013)
        return nil
    }

    /// 이전·현재·다음 줄 중 하나라도 달라졌는지 (같은 줄이 반복돼도 이전·다음 줄이 바뀌면 갱신)
    /// 카운트다운 숫자(3·2·1)가 바뀌어도 갱신 (작업 020)
    static func linesChanged(old: CardSnapshot, new: CardSnapshot) -> Bool {
        textChanged(old, new) || old.countdown != new.countdown
    }

    /// 이전·현재·다음 줄 글자만 비교
    private static func textChanged(_ old: CardSnapshot, _ new: CardSnapshot) -> Bool {
        old.previous != new.previous || old.current != new.current || old.next != new.next
    }

    /// 카드 갱신 로그 한 줄. nil이면 기록 안 함. syncOffset은 싱크 보정으로 갱신할 때만 넘김
    /// 가사 줄 변경은 줄마다 쌓이기만 해서 기록하지 않지만(작업 010), 싱크 보정 때는 이유 뒤에 보정값이 붙어 기록함
    static func logLine(count: Int, reason: CardUpdateReason, syncOffset: Double?) -> String? {
        if let syncOffset {
            return "🪪 카드 갱신 #\(count) — \(reason.text) (싱크 보정 \(String(format: "%+.2f", syncOffset))초)"
        }
        if reason == .lineChanged { return nil }
        return "🪪 카드 갱신 #\(count) — \(reason.text)"
    }

    /// 싱크 보정을 더한 위치 (곡 길이를 넘거나 0 미만이 되지 않게)
    static func position(_ raw: TimeInterval, offset: Double, duration: TimeInterval) -> TimeInterval {
        min(duration, max(0, raw + offset))
    }

    /// 전주·간주 끝 3초의 3·2·1 (작업 020). 싱크 가사 + 재생 중일 때만, 아니면 0
    static func countdown(kind: LyricsKind, isPlaying: Bool, lines: [LyricLine], position: TimeInterval) -> Int {
        guard kind == .synced, isPlaying else { return 0 }
        return LyricCountdown.value(lines, at: position)
    }
}

/// 카드에 쓰는 네 줄 글자
nonisolated struct CardText: Equatable {
    var previous: String
    var current: String
    var next: String
    var trackInfo: String

    /// 가사 종류별 카드 내용
    ///   싱크 가사   : 이전/현재/다음 줄
    ///   일반 가사만 : "싱크 가사가 없어요" 안내 (일반 가사는 저장만 함)
    ///   연주곡      : 🎼 연주곡
    ///   못 찾음     : 아티스트/제목/앨범
    static func make(kind: LyricsKind, lines: [LyricLine], position: TimeInterval,
                     title: String, artist: String, album: String) -> CardText {
        let info = "\(title) · \(artist)"
        switch kind {
        case .synced:
            let ctx = LRCParser.context(lines, at: position)
            return CardText(previous: ctx.previous, current: ctx.current, next: ctx.next, trackInfo: info)
        case .plain:
            return CardText(previous: "", current: "싱크 가사가 없어요", next: "일반 가사만 있어서 저장해 뒀어요", trackInfo: info)
        case .instrumental:
            return CardText(previous: "", current: "🎼 연주곡", next: "", trackInfo: info)
        case .none:
            return CardText(previous: artist, current: title, next: album, trackInfo: "")
        }
    }

    /// 재생 중인 곡이 없을 때
    static func noTrack(status: String) -> CardText {
        CardText(previous: "", current: status, next: "Spotify에서 음악을 재생하세요", trackInfo: "")
    }
}
