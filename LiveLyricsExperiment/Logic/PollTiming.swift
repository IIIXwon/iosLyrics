// 앱 타깃 — 순수 로직 (작업 024: Spotify/NowPlayingService.swift에서 옮김, `swift test` 대상)
import Foundation

/// 곡 끝 무렵 다음 조회까지 기다릴 시간 (작업 021)
nonisolated enum PollTiming {
    /// 곡이 끝났는데 Spotify가 아직 같은 곡을 줄 때 다시 볼 간격(초)
    static let endRecheck: TimeInterval = 1
    /// 끝난 뒤 이 시간(초)까지만 endRecheck 간격으로 다시 봄
    static let endRecheckLimit: TimeInterval = 5
    /// remaining: 곡 끝까지 남은 시간(자르지 않은 값, 끝났으면 음수). 재생 중이 아니면 nil
    /// - nil → base
    /// - 0 < remaining, remaining + 0.5 < base → remaining + 0.5
    /// - -endRecheckLimit < remaining ≤ 0 → min(base, endRecheck)
    /// - 그 밖 → base
    static func wait(base: TimeInterval, remaining: TimeInterval?) -> TimeInterval {
        guard let remaining else { return base }
        if remaining > 0 {
            return remaining + 0.5 < base ? remaining + 0.5 : base
        }
        if remaining > -endRecheckLimit {
            return min(base, endRecheck)
        }
        return base
    }
}

/// SDK 연결 여부에 따른 기본 조회 간격 (작업 025)
extension PollTiming {
    enum State { case playing, paused, none }

    /// 미연결 (작업 008 값 그대로)
    static let playing: TimeInterval = 3
    static let paused: TimeInterval = 15
    static let noTrack: TimeInterval = 10
    /// SDK 연결 중 (이벤트로 바로 알 수 있으니 폴링을 완화)
    static let connectedPlaying: TimeInterval = 15
    static let connectedPaused: TimeInterval = 30

    /// SDK 연결 여부에 따른 기본 조회 간격. 미연결은 지금과 같은 3·15·10초
    static func interval(connected: Bool, state: State) -> TimeInterval {
        switch state {
        case .playing: return connected ? connectedPlaying : playing
        case .paused: return connected ? connectedPaused : paused
        case .none: return noTrack
        }
    }
}
