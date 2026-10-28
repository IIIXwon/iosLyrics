// 앱 타깃 — Spotify iOS SDK(App Remote)를 감싸는 유일한 파일 (작업 025)
//
// SDK는 "보조 출처"로만 써요. 연결돼 있으면 곡 변경·일시정지·재생을 이벤트로 바로 알려 주고,
// 끊기면 지금처럼 Web API 3초 폴링으로 돌아가요 (NowPlayingService).
// - 로그인은 기존 PKCE 토큰(scope에 app-remote-control)을 그대로 씀
// - ⚠️ authorizeAndPlayURI는 쓰지 않음 (Spotify를 강제로 열고 재생시키므로)
// - ⚠️ 재생 제어(재생/일시정지/스킵)는 하지 않음 — 감지 전용. 카드 ▶︎은 지금처럼 Web API
import Foundation
import SpotifyiOS

@MainActor
final class SpotifyRemote: NSObject {
    /// 플레이어 상태가 바뀔 때 (광고·에피소드·해석 실패면 nil)
    var onState: (@MainActor (RemoteSnapshot?) -> Void)?
    /// 연결됨(true) / 끊김(false). 끊긴 이유는 `lastError`
    var onConnectionChange: (@MainActor (Bool) -> Void)?
    /// 연결 시도가 실패했을 때 (이유)
    var onFailure: (@MainActor (String) -> Void)?
    var onLog: (@MainActor (String) -> Void)?

    /// 마지막 끊김·실패 이유 (로그용)
    private(set) var lastError: String?
    private(set) var isConnecting = false
    var isConnected: Bool { appRemote.isConnected }

    private let auth: SpotifyAuth
    private var userDisconnecting = false   // 정지·강제 종료로 우리가 끊는 중

    private lazy var appRemote: SPTAppRemote = {
        let redirect = URL(string: SpotifyConfig.redirectURI) ?? URL(fileURLWithPath: "/")
        let configuration = SPTConfiguration(clientID: SpotifyConfig.clientID, redirectURL: redirect)
        let remote = SPTAppRemote(configuration: configuration, logLevel: .error)
        remote.delegate = self
        return remote
    }()

    init(auth: SpotifyAuth) {
        self.auth = auth
        super.init()
    }

    /// 연결 시도. 이미 연결됐거나 연결 중이면 무시
    func connect() {
        guard !isConnected, !isConnecting else { return }
        isConnecting = true
        userDisconnecting = false
        Task {
            do {
                let token = try await auth.validAccessToken()
                guard isConnecting else { return }   // 토큰을 받는 사이 disconnect()가 불림
                appRemote.connectionParameters.accessToken = token
                appRemote.connect()
            } catch {
                isConnecting = false
                fail("토큰: \(error.localizedDescription)")
            }
        }
    }

    /// 연결 끊기 (추적 정지·앱 강제 종료 때). 백그라운드로 갈 때는 부르지 않음 — 연결 유지가 잠금 상태 이득의 핵심
    func disconnect() {
        guard isConnected || isConnecting else { return }
        userDisconnecting = true
        isConnecting = false
        if isConnected { appRemote.disconnect() }
    }

    private func fail(_ reason: String) {
        lastError = reason
        onFailure?(reason)
    }

    // MARK: - 연결 뒤 구독

    private func didConnect() {
        isConnecting = false
        lastError = nil
        onConnectionChange?(true)
        guard let player = appRemote.playerAPI else {
            onLog?("⚠️ SDK playerAPI 없음")
            return
        }
        player.delegate = self
        player.subscribe(toPlayerState: { [weak self] _, error in
            guard let error else { return }
            let text = error.localizedDescription
            Task { @MainActor in self?.onLog?("⚠️ SDK 상태 구독 실패: \(text)") }
        })
        player.getPlayerState { [weak self] result, error in
            if let error {
                let text = error.localizedDescription
                Task { @MainActor in self?.onLog?("⚠️ SDK 상태 조회 실패: \(text)") }
                return
            }
            guard let state = result as? SPTAppRemotePlayerState else { return }
            let snap = Self.snapshot(state)
            Task { @MainActor in self?.onState?(snap) }
        }
    }

    /// SDK 플레이어 상태 → RemoteSnapshot (광고·에피소드면 nil)
    nonisolated private static func snapshot(_ state: SPTAppRemotePlayerState) -> RemoteSnapshot? {
        let track = state.track
        return RemoteSnapshot.make(
            uri: track.uri, name: track.name, artist: track.artist.name, album: track.album.name,
            durationMs: Int(track.duration), positionMs: state.playbackPosition,
            isPaused: state.isPaused, isAd: track.isAdvertisement
        )
    }
}

// MARK: - SDK 델리게이트 (nonisolated + 메인 액터로 넘김)

extension SpotifyRemote: SPTAppRemoteDelegate {
    nonisolated func appRemoteDidEstablishConnection(_ appRemote: SPTAppRemote) {
        Task { @MainActor in self.didConnect() }
    }

    nonisolated func appRemote(_ appRemote: SPTAppRemote, didFailConnectionAttemptWithError error: Error?) {
        let text = error?.localizedDescription ?? "이유 없음"
        Task { @MainActor in
            self.isConnecting = false
            if self.userDisconnecting { return }
            self.fail(text)
        }
    }

    nonisolated func appRemote(_ appRemote: SPTAppRemote, didDisconnectWithError error: Error?) {
        let text = error?.localizedDescription
        Task { @MainActor in
            self.isConnecting = false
            self.lastError = self.userDisconnecting ? "정지" : (text ?? "이유 없음")
            self.userDisconnecting = false
            self.onConnectionChange?(false)
        }
    }
}

extension SpotifyRemote: SPTAppRemotePlayerStateDelegate {
    nonisolated func playerStateDidChange(_ playerState: SPTAppRemotePlayerState) {
        let snap = Self.snapshot(playerState)
        Task { @MainActor in self.onState?(snap) }
    }
}
