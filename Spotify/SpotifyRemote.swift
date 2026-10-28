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
    /// 마지막 끊김이 우리가 끊은 것(정지·강제 종료)인지. true면 lastError는 끊은 이유
    private(set) var lastDisconnectByUser = false
    private(set) var isConnecting = false
    var isConnected: Bool { appRemote.isConnected }

    /// 연결 시도 후 이 시간(초) 안에 성공·실패 콜백이 없으면 시간 초과로 보고 다시 시도할 수 있게 함
    private let connectTimeout: TimeInterval = 15

    private let auth: SpotifyAuth
    /// 정지·강제 종료로 우리가 끊는 중 (끊긴 이유). 다음 connect()나 끊김·실패 콜백에서 지움
    private var userDisconnectReason: String?
    /// onConnectionChange(true)를 보냈는지 (보낸 적 없으면 끊김도 알리지 않음)
    private var reportedConnected = false
    private var attempt = 0                       // 연결 시도 번호 (이전 시도의 토큰·시간 초과 처리가 섞이지 않게)
    private var timeoutTask: Task<Void, Never>?

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
        userDisconnectReason = nil
        attempt += 1
        let current = attempt
        startTimeout(for: current)
        Task {
            do {
                let token = try await auth.validAccessToken()
                // 토큰을 받는 사이 disconnect()·시간 초과·새 시도가 있었으면 그만둠
                guard isConnecting, attempt == current else {
                    // SDK에 연결을 요청하기 전에 끊었으므로 끊김 콜백이 오지 않음 → 여기서 정리
                    if attempt == current { userDisconnectReason = nil }
                    return
                }
                appRemote.connectionParameters.accessToken = token
                appRemote.connect()
            } catch {
                guard isConnecting, attempt == current else { return }
                endAttempt()
                fail("토큰: \(Self.describe(error))")
            }
        }
    }

    /// 연결 끊기 (추적 정지·앱 강제 종료 때). 백그라운드로 갈 때는 부르지 않음 — 연결 유지가 잠금 상태 이득의 핵심
    /// 연결 시도 중에 불리면, 나중에 연결이 성공해도 didConnect에서 바로 끊음
    func disconnect(reason: String = "정지") {
        guard isConnected || isConnecting else { return }
        userDisconnectReason = reason
        endAttempt()
        if isConnected { appRemote.disconnect() }
    }

    /// 연결 시도 상태를 끝냄 (성공·실패·시간 초과·끊기)
    private func endAttempt() {
        isConnecting = false
        timeoutTask?.cancel()
        timeoutTask = nil
    }

    /// 연결 시도 후 connectTimeout 안에 SDK가 성공·실패를 알려 주지 않으면 시간 초과 처리
    /// (안 그러면 isConnecting이 계속 true라 이후 재시도가 모두 막힘)
    private func startTimeout(for current: Int) {
        timeoutTask?.cancel()
        let nanos = UInt64(connectTimeout * 1_000_000_000)
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled, let self, self.isConnecting, self.attempt == current else { return }
            self.endAttempt()
            self.fail("시간 초과")
        }
    }

    /// 오류를 한 줄로: `<설명> [domain=… code=… ← underlying domain=… code=… <설명>]` (원인 진단용, 작업 025 검토 1차)
    /// NSUnderlyingErrorKey는 한 단계 아래까지만. 토큰 값은 들어가지 않음(SDK 오류 설명·domain·code만)
    nonisolated static func describe(_ error: Error?) -> String {
        guard let error else { return "이유 없음" }
        let ns = error as NSError
        var detail = "domain=\(ns.domain) code=\(ns.code)"
        if let under = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
            detail += " ← underlying domain=\(under.domain) code=\(under.code) \(under.localizedDescription)"
        }
        return "\(ns.localizedDescription) [\(detail)]"
    }

    private func fail(_ reason: String) {
        lastError = reason
        onFailure?(reason)
    }

    // MARK: - 연결 뒤 구독

    private func didConnect() {
        endAttempt()
        // 연결 시도 중에 disconnect()가 불렸음 → 연결됐다고 알리지 않고 바로 끊음
        // (끊김 콜백이 오면 reportedConnected가 false라 알리지 않고 userDisconnectReason을 지움)
        if userDisconnectReason != nil {
            appRemote.disconnect()
            return
        }
        lastError = nil
        reportedConnected = true
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
        let text = Self.describe(error)
        Task { @MainActor in
            self.endAttempt()
            if self.userDisconnectReason != nil {   // 우리가 끊는 중이었음 → 실패로 알리지 않음
                self.userDisconnectReason = nil
                return
            }
            self.fail(text)
        }
    }

    nonisolated func appRemote(_ appRemote: SPTAppRemote, didDisconnectWithError error: Error?) {
        let text = error.map { Self.describe($0) }
        Task { @MainActor in
            self.endAttempt()
            let byUser = self.userDisconnectReason
            self.userDisconnectReason = nil   // 다음 실제 끊김까지 남지 않게
            guard self.reportedConnected else { return }   // 연결됐다고 알린 적 없으면 끊김도 알리지 않음
            self.reportedConnected = false
            self.lastDisconnectByUser = byUser != nil
            self.lastError = byUser ?? text ?? "이유 없음"
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
