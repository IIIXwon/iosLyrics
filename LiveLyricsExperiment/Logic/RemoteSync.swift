// 앱 타깃 — 순수 로직 (작업 025: Spotify iOS SDK를 보조 출처로, `swift test` 대상)
import Foundation

/// SDK 플레이어 상태를 앱이 쓰는 값으로 (작업 025)
nonisolated struct RemoteSnapshot: Equatable {
    var trackID: String
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval   // 초
    var position: TimeInterval   // 초
    var isPlaying: Bool

    private static let trackPrefix = "spotify:track:"

    /// track URI가 아니거나(에피소드 등) id가 비었거나 광고면 nil
    static func make(uri: String, name: String, artist: String, album: String,
                     durationMs: Int, positionMs: Int, isPaused: Bool, isAd: Bool) -> RemoteSnapshot? {
        guard !isAd, uri.hasPrefix(trackPrefix) else { return nil }
        let id = String(uri.dropFirst(trackPrefix.count))
        guard !id.isEmpty else { return nil }
        return RemoteSnapshot(
            trackID: id, title: name, artist: artist, album: album,
            duration: TimeInterval(durationMs) / 1000,
            position: TimeInterval(positionMs) / 1000,
            isPlaying: !isPaused
        )
    }
}

/// SDK 재연결 시도 간격 (작업 025)
nonisolated enum RemoteRetry {
    static let backgroundGap: TimeInterval = 60

    /// foreground(앱 화면 복귀·추적 시작)면 항상 true, 아니면 마지막 시도 후 backgroundGap 이상 지났을 때만
    static func shouldTry(now: TimeInterval, lastAttempt: TimeInterval?, foreground: Bool) -> Bool {
        if foreground { return true }
        guard let lastAttempt else { return true }
        return now - lastAttempt >= backgroundGap
    }
}
