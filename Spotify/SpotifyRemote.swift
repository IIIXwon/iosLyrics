// 앱 타깃 — Spotify iOS SDK(App Remote)를 감싸는 유일한 파일 (작업 025)
//
// SDK는 "보조 출처"로만 써요. 연결돼 있으면 곡 변경·일시정지·재생을 이벤트로 바로 알려 주고,
// 끊기면 지금처럼 Web API 3초 폴링으로 돌아가요 (NowPlayingService).
// - 연결 토큰은 Spotify 앱 승인 세션(SPTSessionManager)의 토큰 (검토 2차: Web API PKCE 토큰은 Spotify 앱이 거부함)
//   승인은 사용자가 [Spotify 앱 연결]을 눌렀을 때만. 세션은 키체인(AfterFirstUnlock)에 저장하고 앱 시작 때 복원
// - Web API 로그인·토큰(폴링용)은 그대로 SpotifyAuth가 맡음
// - ⚠️ authorizeAndPlayURI·재생 URI 설정은 쓰지 않음 (Spotify를 강제로 열고 재생시키므로)
// - ⚠️ 재생 제어(재생/일시정지/스킵)는 하지 않음 — 감지 전용. 앱 어디서도 재생 제어를 하지 않음 (작업 026)
// - ⚠️ SDK 타입(SPT…)은 이 파일 밖으로 내보내지 않음 — 밖에는 Bool·TimeInterval·RemoteSnapshot 같은 값만
// - ⚠️ 토큰·세션 값은 어떤 로그에도 넣지 않음 (남은 시간·있음/없음만)
import Combine
import Foundation
import SpotifyiOS
import UIKit

@MainActor
final class SpotifyRemote: NSObject, ObservableObject {
    /// connect()가 한 일 — 컨트롤러는 이 결과로 시도 줄·안내를 판단 (검토 2차 리뷰)
    enum ConnectStart: Equatable {
        /// 연결을 시작함. renewing이면 세션 갱신 후 연결 (진행 중인 갱신이 있으면 그 결과를 기다림)
        case started(renewing: Bool)
        /// 이미 연결됐거나 연결 중 → 아무것도 하지 않음
        case busy
        /// [Spotify 앱 연결] 승인 결과를 기다리는 중 (요청 후 authorizeWait 초까지) → 시도·안내하지 않음
        case authorizing
        /// 승인 세션이 없거나 갱신할 수 없음 → 시도하지 않음
        case needAuthorize
    }

    /// 플레이어 상태가 바뀔 때 (광고·에피소드·해석 실패면 nil)
    var onState: (@MainActor (RemoteSnapshot?) -> Void)?
    /// 연결됨(true) / 끊김(false). 끊긴 이유는 `lastError`
    var onConnectionChange: (@MainActor (Bool) -> Void)?
    /// 연결 시도가 실패했을 때 (이유 상세, 같은 실패인지 비교할 키 — `domain=… code=…` / 세션 갱신 단계는 앞에 "세션 갱신")
    var onFailure: (@MainActor (String, String) -> Void)?
    /// Spotify 앱 승인이 끝나 새 세션을 받았을 때 (컨트롤러가 바로 연결을 시도)
    var onAuthorized: (@MainActor () -> Void)?
    var onLog: (@MainActor (String) -> Void)?

    /// 지금 세션으로 연결할 수 있는지 (화면의 [Spotify 앱 연결] 버튼 판단용). `updateAuthAction()`으로 다시 계산
    @Published private(set) var authAction: RemoteAuthPlan.Action = .needAuthorize

    /// 마지막 끊김·실패 이유 (로그용)
    private(set) var lastError: String?
    /// 마지막 끊김이 우리가 끊은 것(정지·강제 종료)인지. true면 lastError는 끊은 이유
    private(set) var lastDisconnectByUser = false
    private(set) var isConnecting = false
    var isConnected: Bool { appRemote.isConnected }

    /// 승인 세션이 있는지 (값은 노출하지 않음)
    var hasSession: Bool { session != nil }
    /// 승인 세션 토큰의 남은 유효 시간(초). 세션 없으면 nil
    var sessionRemaining: TimeInterval? { session?.expirationDate.timeIntervalSinceNow }

    /// 연결 시도 후 이 시간(초) 안에 성공·실패 콜백이 없으면 시간 초과로 보고 다시 시도할 수 있게 함 (세션 갱신 포함)
    private let connectTimeout: TimeInterval = 15
    /// [Spotify 앱 연결] 후 이 시간(초)까지는 승인 결과를 기다리는 중으로 봄 ("연결 필요" 안내·시도 기록 안 함)
    private let authorizeWait: TimeInterval = 30
    /// 세션 갱신 요청 후 이 시간(초)이 지나도 결과가 없으면 SDK가 응답하지 않는 것으로 보고 다시 요청할 수 있게 함
    private let renewStaleAfter: TimeInterval = 60

    /// 정지·강제 종료로 우리가 끊는 중 (끊긴 이유). 다음 connect()나 끊김·실패 콜백에서 지움
    private var userDisconnectReason: String?
    /// onConnectionChange(true)를 보냈는지 (보낸 적 없으면 끊김도 알리지 않음)
    private var reportedConnected = false
    private var attempt = 0                       // 연결 시도 번호 (이전 시도의 갱신·시간 초과 처리가 섞이지 않게)
    private var timeoutTask: Task<Void, Never>?

    /// Spotify 앱 승인 세션 (키체인에서 복원). ⚠️ 값은 로그에 넣지 않음
    private var session: SPTSession?
    private static let sessionKey = "spotify.sdkSession"

    /// 세션 세대 번호. 로그아웃(clearSession)마다 1 올림 → 그 전에 시작한 승인·갱신의 결과는 버림 (검토 2차 리뷰)
    private var generation = 0
    /// SDK에 보낸 요청(승인·갱신)이 시작된 세대와 시각(기기 가동 시간). 결과가 오면 nil
    private struct Pending {
        let generation: Int
        let startedAt: TimeInterval
    }
    /// [Spotify 앱 연결]로 보낸 승인 요청
    private var authorizing: Pending?
    /// SDK에 보낸 세션 갱신 요청 (renewSession). 진행 중이면 다시 부르지 않음
    private var renewing: Pending?
    /// 세션 갱신 결과를 기다리는 연결 시도 번호 (없으면 nil). 시간 초과·끊기·로그아웃에서 지움
    private var renewingFor: Int?

    /// SDK 설정 — 기존 Client ID·`livelyrics://callback`. tokenSwap/Refresh URL은 nil(SDK가 PKCE로 교환), 재생 URI는 설정하지 않음
    private lazy var configuration: SPTConfiguration = {
        let redirect = URL(string: SpotifyConfig.redirectURI) ?? URL(fileURLWithPath: "/")
        return SPTConfiguration(clientID: SpotifyConfig.clientID, redirectURL: redirect)
    }()

    private lazy var appRemote: SPTAppRemote = {
        let remote = SPTAppRemote(configuration: configuration, logLevel: .error)
        remote.delegate = self
        return remote
    }()

    /// 처음 필요할 때(승인·갱신·돌아온 주소) 만듦. 로그아웃만으로는 만들지 않음
    private var sessionManagerStorage: SPTSessionManager?
    private var sessionManager: SPTSessionManager {
        if let sessionManagerStorage { return sessionManagerStorage }
        let manager = SPTSessionManager(configuration: configuration, delegate: self)
        manager.session = session   // 복원한 세션으로 갱신(renewSession)할 수 있게
        sessionManagerStorage = manager
        return manager
    }

    override init() {
        super.init()
        session = Self.loadSession()
        updateAuthAction()
    }

    private static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    /// 이번 세대의 요청이고 아직 limit 초가 지나지 않았는지
    private func isActive(_ pending: Pending?, within limit: TimeInterval) -> Bool {
        guard let pending, pending.generation == generation else { return false }
        return Self.now - pending.startedAt < limit
    }

    // MARK: - Spotify 앱 승인 (검토 2차)

    /// 세션 상태로 연결 방법을 다시 계산 (시간이 지나 만료에 가까워졌을 수 있으므로 판단 직전에 부름)
    func updateAuthAction() {
        let canRenew = !(session?.refreshToken.isEmpty ?? true)
        let action = RemoteAuthPlan.action(hasSession: session != nil, expiresIn: sessionRemaining, canRenew: canRenew)
        if action != authAction { authAction = action }
    }

    /// [Spotify 앱 연결]·카드 탭 재연결(작업 029): Spotify 앱으로 넘어가 승인 → `livelyrics://callback`으로 돌아옴. 음악은 재생하지 않음
    /// - Returns: 승인 요청을 보냈으면 true, 세션 갱신 중이라 건너뛰었으면 false
    @discardableResult
    func authorize() -> Bool {
        // 세션 갱신 결과를 기다리는 중이면 승인 요청을 겹치지 않음 (SDK 실패 콜백이 하나라 둘을 구분할 수 없게 됨)
        if isActive(renewing, within: renewStaleAfter) {
            onLog?("⚡ SDK 세션 갱신 중이에요 — 잠시 후 다시 눌러 주세요")
            return false
        }
        renewing = nil
        authorizing = Pending(generation: generation, startedAt: Self.now)
        onLog?("⚡ Spotify 앱으로 이동해 승인 요청 (음악은 재생하지 않아요)")
        sessionManager.initiateSession(with: .appRemoteControl, options: .clientOnly, campaign: nil)
        return true
    }

    /// Spotify 앱 승인 후 돌아온 주소 처리. SDK가 알아본 주소면 true (결과는 세션 델리게이트로 옴)
    @discardableResult
    func handleAuthCallback(_ url: URL) -> Bool {
        sessionManager.application(UIApplication.shared, open: url, options: [:])
    }

    /// 로그아웃 때: 연결을 끊고 승인 세션을 메모리·키체인에서 지움. 세대를 올려 진행 중인 승인·갱신 결과는 버림
    func clearSession() {
        disconnect(reason: "로그아웃")
        generation += 1
        renewingFor = nil
        session = nil
        sessionManagerStorage?.session = nil   // 아직 안 만들었으면 만들지 않음
        Keychain.delete(Self.sessionKey)
        updateAuthAction()
    }

    private static func loadSession() -> SPTSession? {
        guard let data = Keychain.readData(sessionKey) else { return nil }
        return unarchive(data)
    }

    /// 세션 → Data (NSSecureCoding). 델리게이트(메인 액터 밖)에서 메인 액터로 넘길 때도 이 값으로 넘김
    nonisolated private static func archive(_ session: SPTSession) -> Data? {
        try? NSKeyedArchiver.archivedData(withRootObject: session, requiringSecureCoding: true)
    }

    nonisolated private static func unarchive(_ data: Data) -> SPTSession? {
        try? NSKeyedUnarchiver.unarchivedObject(ofClass: SPTSession.self, from: data)
    }

    /// 새 세션(승인·갱신)을 저장. 실패하면 nil
    private func store(_ data: Data?) -> SPTSession? {
        guard let data, let restored = Self.unarchive(data) else {
            onLog?("⚠️ Spotify 앱 승인 세션을 저장하지 못했어요")
            return nil
        }
        Keychain.saveData(data, for: Self.sessionKey)
        session = restored
        updateAuthAction()
        return restored
    }

    private static func minutesText(_ seconds: TimeInterval?) -> String {
        guard let seconds else { return "알 수 없음" }
        return "\(max(0, Int(seconds / 60)))분"
    }

    /// 로그아웃(세대 변경) 전에 시작한 요청의 결과 → 저장·연결하지 않고 버림
    private func ignoreStale() {
        onLog?("⚡ 로그아웃 뒤 도착한 승인 결과 무시")
    }

    private func sessionInitiated(_ data: Data?) {
        guard let pending = authorizing, pending.generation == generation else {
            if authorizing != nil { authorizing = nil }
            ignoreStale()
            return
        }
        authorizing = nil
        guard store(data) != nil else { return }
        onLog?("⚡ Spotify 앱 승인 완료 (만료까지 \(Self.minutesText(sessionRemaining)))")
        onAuthorized?()
    }

    private func sessionRenewed(_ data: Data?) {
        guard let pending = renewing, pending.generation == generation else {
            if renewing != nil { renewing = nil }
            ignoreStale()
            return
        }
        renewing = nil
        let renewed = store(data)
        if renewed != nil { onLog?("⚡ SDK 세션 갱신됨 (만료까지 \(Self.minutesText(sessionRemaining)))") }
        // 갱신을 기다리는 시도가 없으면(시간 초과·끊기로 지워짐) 저장만 함
        guard let current = renewingFor else { return }
        renewingFor = nil
        guard isConnecting, attempt == current else { return }
        guard let renewed else {
            endAttempt()
            fail("세션 갱신 결과를 읽지 못함", key: "세션 갱신 저장 실패")
            return
        }
        connectAppRemote(token: renewed.accessToken)
    }

    /// 승인 또는 갱신 실패. SDK는 둘을 같은 콜백으로 알려 주므로 이번 세대에 보낸 요청으로 구분
    /// (갱신 중에는 승인 요청을 받지 않으므로 둘이 동시에 이번 세대일 수 없음)
    private func sessionFailed(_ text: String, key: String) {
        if let pending = renewing, pending.generation == generation {
            renewing = nil
            onLog?("⚡ SDK 세션 갱신 실패: \(text)")
            guard let current = renewingFor else { return }
            renewingFor = nil
            guard isConnecting, attempt == current else { return }
            endAttempt()
            fail("세션 갱신 실패", key: "세션 갱신 " + key)
            return
        }
        if let pending = authorizing, pending.generation == generation {
            authorizing = nil
            onLog?("⚡ Spotify 앱 승인 실패: \(text)")
            return
        }
        // 이번 세대에 보낸 요청이 없음 → 로그아웃 전 요청의 결과
        renewing = nil
        authorizing = nil
        ignoreStale()
    }

    // MARK: - 연결

    /// 연결 시도. 판단(이미 연결·연결 중 / 승인 대기 / 승인 필요 / 갱신 후 연결 / 연결)은 여기서 하고 결과를 돌려줌
    @discardableResult
    func connect() -> ConnectStart {
        guard !isConnected, !isConnecting else { return .busy }
        updateAuthAction()
        // 승인 결과를 기다리는 중이면 세션이 있어도 연결하지 않음 (작업 029)
        // 왕복 뒤 화면 복귀(appBecameActive)가 새 세션보다 먼저 와서 옛 세션으로 연결을 시작하면
        // isConnecting 때문에 onAuthorized의 연결이 막힘 → 새 세션을 받은 onAuthorized에서 1번 연결
        if isActive(authorizing, within: authorizeWait) { return .authorizing }
        guard authAction != .needAuthorize, let session else { return .needAuthorize }
        isConnecting = true
        userDisconnectReason = nil
        attempt += 1
        let current = attempt
        startTimeout(for: current)
        if authAction == .renew {
            renewingFor = current
            // 이전 시도가 보낸 갱신이 아직 진행 중이면 다시 부르지 않고 그 결과를 기다림
            if !isActive(renewing, within: renewStaleAfter) {
                renewing = Pending(generation: generation, startedAt: Self.now)
                sessionManager.renewSession()
            }
            return .started(renewing: true)
        }
        connectAppRemote(token: session.accessToken)
        return .started(renewing: false)
    }

    private func connectAppRemote(token: String) {
        appRemote.connectionParameters.accessToken = token
        appRemote.connect()
    }

    /// 연결 끊기 (추적 정지·앱 강제 종료·로그아웃 때). 백그라운드로 갈 때는 부르지 않음 — 연결 유지가 잠금 상태 이득의 핵심
    /// 연결 시도 중에 불리면, 나중에 연결이 성공해도 didConnect에서 바로 끊음
    func disconnect(reason: String = "정지") {
        guard isConnected || isConnecting else { return }
        if renewingFor != nil {
            // 세션 갱신을 기다리던 중 → SDK에 연결을 요청하기 전이라 끊김 콜백이 오지 않음. 시도만 끝냄
            endAttempt()
            return
        }
        userDisconnectReason = reason
        endAttempt()
        if isConnected { appRemote.disconnect() }
    }

    /// 연결 시도 상태를 끝냄 (성공·실패·시간 초과·끊기). 갱신을 기다리던 시도 표시도 지움
    private func endAttempt() {
        isConnecting = false
        renewingFor = nil
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
            self.fail("시간 초과", key: "시간 초과")
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

    /// 같은 실패인지 비교할 키: `domain=… code=…` (설명 문구는 빼서, 문구만 다른 같은 오류를 한 번만 자세히 남기게)
    /// 반복 실패 줄에 그대로 보여 주므로 읽을 수 있는 형태로 둠
    nonisolated static func failureKey(_ error: Error?) -> String {
        guard let error else { return "이유 없음" }
        let ns = error as NSError
        return "domain=\(ns.domain) code=\(ns.code)"
    }

    private func fail(_ reason: String, key: String) {
        lastError = reason
        onFailure?(reason, key)
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

extension SpotifyRemote: SPTSessionManagerDelegate {
    nonisolated func sessionManager(manager: SPTSessionManager, didInitiate session: SPTSession) {
        let data = Self.archive(session)   // 메인 액터로는 Data로 넘김 (SDK 객체를 넘기지 않음)
        Task { @MainActor in self.sessionInitiated(data) }
    }

    nonisolated func sessionManager(manager: SPTSessionManager, didFailWith error: Error) {
        let text = Self.describe(error)
        let key = Self.failureKey(error)
        Task { @MainActor in self.sessionFailed(text, key: key) }
    }

    nonisolated func sessionManager(manager: SPTSessionManager, didRenew session: SPTSession) {
        let data = Self.archive(session)
        Task { @MainActor in self.sessionRenewed(data) }
    }
}

extension SpotifyRemote: SPTAppRemoteDelegate {
    nonisolated func appRemoteDidEstablishConnection(_ appRemote: SPTAppRemote) {
        Task { @MainActor in self.didConnect() }
    }

    nonisolated func appRemote(_ appRemote: SPTAppRemote, didFailConnectionAttemptWithError error: Error?) {
        let text = Self.describe(error)
        let key = Self.failureKey(error)
        Task { @MainActor in
            self.endAttempt()
            if self.userDisconnectReason != nil {   // 우리가 끊는 중이었음 → 실패로 알리지 않음
                self.userDisconnectReason = nil
                return
            }
            self.fail(text, key: key)
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
