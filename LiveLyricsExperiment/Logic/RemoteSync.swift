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

/// SDK 연결 전 승인 상태 판단 (작업 025 검토 2차: Spotify 앱 승인 세션)
nonisolated enum RemoteAuthPlan {
    enum Action: Equatable { case connect, renew, needAuthorize }

    /// 만료까지 이 시간(초) 이하로 남았으면 연결 전에 갱신
    static let renewMargin: TimeInterval = 60

    /// expiresIn: 세션 만료까지 남은 초(세션 없으면 nil). canRenew: 세션에 refresh token이 있는지
    /// - 세션 없음 → needAuthorize / expiresIn > renewMargin → connect / 그 밖: canRenew ? renew : needAuthorize
    static func action(hasSession: Bool, expiresIn: TimeInterval?, canRenew: Bool) -> Action {
        guard hasSession, let expiresIn else { return .needAuthorize }
        if expiresIn > renewMargin { return .connect }
        return canRenew ? .renew : .needAuthorize
    }

    /// 세션 갱신이 연속 이 횟수만큼 실패하면 갱신을 포기하고 승인 왕복으로 새 세션을 받음 (작업 030)
    static let renewGiveUpAfter = 2

    /// refresh token이 있고 연속 갱신 실패가 renewGiveUpAfter 미만이면 true (작업 030)
    static func canRenew(hasRefreshToken: Bool, renewFailures: Int) -> Bool {
        hasRefreshToken && renewFailures < renewGiveUpAfter
    }

    /// [Spotify 앱 연결] 버튼: Web API 로그인돼 있고 SDK 승인이 필요할 때만
    static func showsAuthorizeButton(loggedIn: Bool, action: Action) -> Bool {
        loggedIn && action == .needAuthorize
    }
}

/// 잠금화면 카드 탭 때 할 일 (작업 029)
nonisolated enum CardTapPlan {
    enum Action: Equatable {
        /// Spotify 앱만 열기 (작업 026 그대로)
        case openSpotify
        /// Spotify 승인 왕복(initiateSession .clientOnly, 재생 안 함)으로 SDK 다시 연결
        case reconnect
    }

    /// 추적 중 + Web API 로그인 + SDK 미연결 + 승인 세션으로 연결 가능(authAction != .needAuthorize)이면 .reconnect, 그 밖은 .openSpotify
    /// 연결 시도 중이어도 .reconnect (029 리뷰 수용 A): 카드 탭으로 앱이 열릴 때 화면 복귀가 먼저 와서 옛 세션으로 시도가 시작돼 있을 수 있음
    /// → 왕복으로 새 세션을 받고, 진행 중인 시도가 끝나면 새 세션으로 다시 연결 (ExperimentController.remoteConnectAfterAttempt)
    /// hasSession: 키체인에 승인 세션이 있음(= 한 번 승인함, 작업 030) → needAuthorize여도(만료·갱신 불가) 승인 왕복으로 재승인
    /// 세션이 없으면(첫 승인 전·로그아웃 뒤) 승인 화면을 띄우지 않고 Spotify만 연다
    static func action(isRunning: Bool, loggedIn: Bool, remoteConnected: Bool,
                       authAction: RemoteAuthPlan.Action, hasSession: Bool = false) -> Action {
        guard isRunning, loggedIn, !remoteConnected,
              authAction != .needAuthorize || hasSession else { return .openSpotify }
        return .reconnect
    }
}
