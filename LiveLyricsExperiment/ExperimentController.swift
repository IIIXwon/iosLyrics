// 앱 타깃 — 전체 조율: Spotify 재생 정보와 싱크 가사를 잠금화면 카드(Live Activity)에 표시
//
// 잠금화면 카드
//   가사가 있을 때 : 이전 줄 / 현재 줄 / 다음 줄 (제목·시간·진행 막대 없음, 작업 013)
//   가사가 없을 때 : 아티스트 / 곡 제목 / 앨범
//
// 카드는 "바뀐 게 있을 때만" 갱신
//   - 처음, 곡 변경, 재생/일시정지 변경, 표시 내용(가사 줄) 변경
import ActivityKit
import AuthenticationServices
import Combine
import Foundation
import SwiftUI
import UIKit

@MainActor
final class ExperimentController: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var logs: [String] = []

    /// 싱크 보정(초). + 이면 카드 시간을 앞당기고, - 이면 늦춤. 앱을 껐다 켜도 유지
    @Published var syncOffset: Double = UserDefaults.standard.object(forKey: "syncOffset") as? Double ?? 0.25 {
        didSet {
            UserDefaults.standard.set(syncOffset, forKey: "syncOffset")
            guard syncOffset != oldValue, isRunning, let np = nowPlaying.current else { return }
            let state = makeState(np)
            if let reason = updateReason(new: state, key: np.key) {
                sendCard(state, key: np.key, reason: "\(reason) (싱크 보정 \(String(format: "%+.2f", syncOffset))초)")
            }
            // 보정값이 바뀌면 다음 줄·카운트다운 예약 시각도 달라지므로 새로 잡음 (작업 020 리뷰 1차)
            scheduleNextLine()
        }
    }

    let auth = SpotifyAuth()
    let nowPlaying: NowPlayingService
    let location = LocationKeepAlive()
    let readiness: ReadinessModel          // 작업 004: 화면 맨 위의 "준비 상태"
    private let api: SpotifyAPI

    // Spotify iOS SDK — 보조 출처 (작업 025). 연결돼 있으면 이벤트로 바로 반영, 끊기면 3초 폴링 그대로
    let remote: SpotifyRemote
    private var remoteLastAttempt: TimeInterval?   // 마지막 연결 시도 시각 (기기 가동 시간 기준)
    private var remoteLastFailure: String?          // 같은 이유의 실패 로그를 연속으로 남기지 않으려고

    private var activity: Activity<LyricsActivityAttributes>?
    private var activityUpdates = 0
    private var skippedUpdates = 0
    private var lastSent: LyricsActivityAttributes.ContentState?
    private var lastSentKey: String?

    // 카드 상태 로그 (작업 019, 023 지연 측정에 씀)
    private var activityStateTask: Task<Void, Never>?               // 카드 상태 변화(activityStateUpdates) 구독

    // 3단계: 현재 곡의 싱크 가사 (없으면 빈 배열)
    private var lyrics: [LyricLine] = []          // 싱크 가사일 때만 채워짐
    private var lyricsKind: LyricsKind = .none
    private var lyricsKey: String?
    private var lyricsTask: Task<Void, Never>?
    private var lineTask: Task<Void, Never>?

    // 다음 곡 가사 미리 받기 (작업 021)
    private var prefetchTasks: [Int: Task<Void, Never>] = [:]   // 진행 중인 미리 받기 전체 (번호별) — 정지할 때 모두 취소
    private var prefetchingKeys: [String: Int] = [:]            // 대기열 조회가 끝나 받을 곡이 정해진 미리 받기 (곡 key → 번호)
    private var prefetchID = 0                                  // 미리 받기 번호
    private var prefetchStartedFor: String?                     // 미리 받기를 이미 시작한 현재 곡 key (곡당 대기열 조회 1번)
    private var lyricsSettledKey: String?                       // 가사 처리(저장본·검색·연주곡)가 끝난 현재 곡 key
    private var prefetchedKeys: [String] = []                   // 최근에 미리 받기를 시도한 곡 key (최대 LyricsPrefetch.memory개)

    // 재생이 멈춘 뒤 이 시간이 지나면 위치 추적을 끔 (배터리 절약)
    private let idleGrace: TimeInterval = 180
    private var idleTask: Task<Void, Never>?

    // 카드의 안내 문구를 폴링이 덮어쓰지 않게 붙잡아 두는 상태 (작업 001)
    private var idleNoticeShown = false     // "▶︎를 누르면 가사가 다시 나와요" — 재생이 다시 시작될 때까지 유지
    private var noticeUntil: Date?          // "Spotify 앱을 한 번 열어 주세요" 같은 짧은 안내 — 몇 초 동안 유지
    private var lastPollAt: Date?           // 직전 조회 시각 (조회 사이가 벌어졌는지 = 앱이 중단됐었는지 확인용)
    private var afterPlayTask: Task<Void, Never>?   // ▶︎ 이후 10분 동안 1분마다 찍는 확인용 로그 (작업 007)
    private var playRequestInProgress = false       // 재생 요청(재시도 포함)이 진행 중인지 — 겹쳐 시작하지 않으려고 (작업 007 수정 1차)
    private var quotaNoticeText: String?            // 호출 한도 차단 중 카드에 띄우는 안내 (nil이면 차단 상태 아님) (작업 008)

    /// 앱 전체에서 하나만 쓰는 컨트롤러. 카드 버튼(인텐트)이 화면 없이 앱을 깨울 때도 같은 것을 써야 해서 공유함
    static let shared = ExperimentController()

    private init() {
        api = SpotifyAPI(auth: auth)
        nowPlaying = NowPlayingService(api: api)
        remote = SpotifyRemote(auth: auth)
        readiness = ReadinessModel(auth: auth, location: location)
        // 작업 009의 SDK 실험 스위치 값은 더 이상 쓰지 않으므로 지움 (작업 010)
        UserDefaults.standard.removeObject(forKey: "sdkExperimentEnabled")
        // 일시정지 중 곡 유지 기간 = 위치 추적을 끄는 시점(idleGrace) + 안내 카드를 먼저 그릴 여유 10초
        nowPlaying.pausedHoldLimit = idleGrace + 10

        readiness.onLog = { [weak self] in self?.log($0) }
        location.onAuthorizationChange = { [weak self] in self?.readiness.refresh() }
        location.onLog = { [weak self] in self?.log($0) }
        nowPlaying.onLog = { [weak self] in self?.log($0) }
        nowPlaying.onUpdate = { [weak self] np, changed in self?.didUpdate(np, trackChanged: changed) }
        nowPlaying.onBlocked = { [weak self] until, body in self?.handleQuotaBlock(until: until, body: body) }
        remote.onState = { [weak self] in self?.nowPlaying.applyRemote($0) }
        remote.onConnectionChange = { [weak self] in self?.remoteConnectionChanged($0) }
        remote.onFailure = { [weak self] in self?.remoteConnectFailed($0) }
        remote.onLog = { [weak self] in self?.log($0) }

        if !SpotifyConfig.isConfigured {
            log("⚠️ SpotifyConfig.swift에 Client ID를 넣어 주세요")
        }

        // 앱 전환기에서 앱을 지우면(강제 종료) 카드도 바로 종료 (작업 014)
        NotificationCenter.default.addObserver(
            forName: UIApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleAppTermination() }
        }

        // 앱이 새로 시작됐을 때 남아 있는 카드가 있으면 이어받음 (작업 006). 없애지 않음
        adoptExistingActivities()
    }

    /// 앱이 강제 종료될 때(iOS가 알림을 보냄) 카드를 동기로 종료 (작업 014)
    /// 이 함수가 끝나면 프로세스도 끝나므로, 종료가 끝날 때까지 최대 2초 기다림.
    /// ⚠️ wait 동안 메인 스레드가 막히므로 end는 메인 액터와 무관한 Task.detached에서 하고, 그 안에서 self를 쓰지 않음 (데드락 방지)
    /// userStopped는 바꾸지 않음 → 다시 열면 자동 시작
    private func handleAppTermination() {
        let semaphore = DispatchSemaphore(value: 0)
        // 카드 종료를 가장 먼저 시작 (아래 메인 작업보다 앞서 end 요청이 나가도록). 여러 카드는 동시에 종료
        Task.detached {
            await withTaskGroup(of: Void.self) { group in
                for old in Activity<LyricsActivityAttributes>.activities {
                    group.addTask { await old.end(nil, dismissalPolicy: .immediate) }
                }
            }
            semaphore.signal()
        }
        log("🛑 앱 강제 종료 → 카드 종료")
        nowPlaying.stop()
        remote.disconnect()
        location.stop()
        _ = semaphore.wait(timeout: .now() + 2)
    }

    // MARK: - 로그인

    func login(using session: WebAuthenticationSession) async {
        do {
            let url = try auth.makeAuthorizeURL()
            let callback = try await session.authenticate(
                using: url, callbackURLScheme: SpotifyConfig.callbackScheme)
            try await auth.handleCallback(callback)
            log("✅ Spotify 로그인 성공")
            readiness.refresh()
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            log("ℹ️ 로그인을 취소했어요")
        } catch {
            log("❌ 로그인 실패: \(error.localizedDescription)")
        }
    }

    func logout() {
        if isRunning { stopTracking() }   // 로그아웃은 "사용자가 정지함"으로 치지 않음
        auth.logout()
        log("👋 로그아웃")
        readiness.refresh()
    }

    /// 백그라운드 없이 한 번만 조회 (연결 확인용)
    func checkOnce() {
        nowPlaying.start()
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if !isRunning { nowPlaying.stop() }
        }
    }

    // MARK: - 시작 / 정지

    /// 사용자가 [시작]을 누름. "사용자가 정지함" 상태를 해제하고 시작
    func start() {
        userStopped = false
        beginTracking(adopting: nil)
    }

    /// 사용자가 [정지]를 누름. 앱을 다시 열어도 자동으로 시작하지 않도록 기억해 둠
    func stop() {
        userStopped = true
        stopTracking()
    }

    /// "사용자가 정지함" 상태 (앱을 껐다 켜도 유지). [시작]을 다시 누르거나 단축어로 실행하면 해제
    private var userStopped: Bool {
        get { UserDefaults.standard.bool(forKey: "userStoppedTracking") }
        set { UserDefaults.standard.set(newValue, forKey: "userStoppedTracking") }
    }

    /// 추적 시작의 공통 흐름. adopting이 있으면 새 카드를 만들지 않고 그 카드를 이어받음
    @discardableResult
    private func beginTracking(adopting existing: Activity<LyricsActivityAttributes>?) -> Bool {
        guard !isRunning else { return false }
        guard auth.isLoggedIn else {
            log("⚠️ 먼저 Spotify에 로그인해 주세요")
            return false
        }
        if existing == nil {
            guard ActivityAuthorizationInfo().areActivitiesEnabled else {
                log("❌ Live Activity가 꺼져 있어요 → 설정 → 이 앱 → 실시간 현황 켜기")
                return false
            }
            guard location.start() else { return false }
        } else if !location.start() {
            // 이어받는 경우에는 위치 추적이 안 켜져도 카드는 이어받음 (카드 ▶︎ 버튼으로 다시 켤 수 있음)
            log("⚠️ 위치 추적을 켜지 못했어요 — 권한: \(location.authorizationText)")
        }

        activityUpdates = 0
        skippedUpdates = 0
        lastSent = nil
        lastSentKey = nil
        idleNoticeShown = false
        noticeUntil = nil
        quotaNoticeText = nil
        lastPollAt = nil
        if auth.needsRelogin {
            log("⚠️ 카드 ▶︎ 버튼(재생 제어)용 새 권한이 필요해요 → 로그아웃 후 Spotify에 다시 로그인")
        }

        if let existing {
            activity = existing
            log("✅ 기존 잠금화면 카드를 이어받아 추적 재개")
        } else {
            do {
                activity = try Activity.request(
                    attributes: LyricsActivityAttributes(title: "Spotify", artist: ""),
                    content: ActivityContent(state: makeState(nil), staleDate: nil),
                    pushType: nil
                )
                log("✅ 잠금화면 카드 시작")
            } catch {
                log("❌ Live Activity 시작 실패: \(error.localizedDescription)")
                location.stop()
                return false
            }
        }
        if let activity { watchActivityState(activity) }

        isRunning = true
        nowPlaying.start()
        log("▶️ 추적 시작 — 조회 간격 \(Int(nowPlaying.interval))초")
        tryRemoteConnect(foreground: true)   // SDK 연결 시점 1: 추적 시작 (작업 025)
        return true
    }

    private func stopTracking() {
        afterPlayTask?.cancel()
        afterPlayTask = nil
        quotaNoticeText = nil
        nowPlaying.stop()
        spotifyWaitTask?.cancel()
        spotifyWaitTask = nil
        resetLyrics()
        cancelPrefetches()
        idleTask?.cancel()
        idleTask = nil
        idleNoticeShown = false
        noticeUntil = nil
        activityStateTask?.cancel()
        activityStateTask = nil
        let ending = activity
        activity = nil
        Task { await ending?.end(nil, dismissalPolicy: .immediate) }
        location.stop()
        remote.disconnect()
        remoteLastAttempt = nil
        isRunning = false
        log("⏹ 정지 (조회 \(nowPlaying.pollCount)회, 카드 갱신 \(activityUpdates)회, 갱신 생략 \(skippedUpdates)회)")
    }

    // MARK: - 자동 시작 · 카드 이어받기 · 단축어 (작업 006)

    private var autoStartInProgress = false

    /// 앱이 화면으로 올 때(처음 실행 포함) 호출. 준비 상태가 모두 ✅이고 추적 중이 아니면 자동으로 시작
    /// 준비 상태에 ❌가 있으면 아무것도 하지 않음 (권한 창도 띄우지 않음)
    func autoStartIfNeeded() async {
        resumeAfterQuotaBlockIfExpired()   // 한도 차단 재개 시각이 지났으면 조회를 다시 시작
        guard !isRunning, !autoStartInProgress else { return }
        autoStartInProgress = true
        defer { autoStartInProgress = false }

        await readiness.refreshAndWait()
        guard !isRunning, !readiness.hasProblem else { return }
        if userStopped {
            log("⏸ 자동 시작 안 함 — 사용자가 정지해 둠")
            return
        }
        log("🚀 자동 시작 (앱 열림)")
        beginTracking(adopting: nil)
    }

    /// 단축어 "가사 추적 시작". 앱을 화면에 띄우지 않고 실행됨 (실험: 백그라운드에서 카드·위치 추적이 시작되는지)
    func startFromShortcut() async {
        log("⚡️ 단축어로 실행 — 앱 상태: \(appStateName()) · 위치 권한: \(location.authorizationText) · 추적 \(isRunning ? "중" : "아님")")
        resumeAfterQuotaBlockIfExpired()
        if let until = SpotifyBlock.until {
            log("⛔️ 한도 차단 중 — \(SpotifyBlock.untilText(until)) 이후 재개")
            return
        }
        guard !isRunning else {
            log("ℹ️ 이미 추적 중")
            return
        }
        userStopped = false   // 사용자가 명시적으로 실행한 것이므로 "정지함" 상태를 해제

        // 남아 있는 카드가 있으면 이어받고, 없으면 새로 시작
        let (keep, others) = Self.pickActivityToAdopt()
        if !others.isEmpty { Task { for old in others { await old.end(nil, dismissalPolicy: .immediate) } } }
        let started = beginTracking(adopting: keep)
        log(started
            ? "⚡️ 단축어 결과: 추적 시작됨 (\(keep != nil ? "기존 카드 이어받음" : "새 카드")) — 앱 상태: \(appStateName())"
            : "⚡️ 단축어 결과: 시작하지 못했어요 (위 로그의 이유 참고) — 앱 상태: \(appStateName())")
        guard started else { return }

        // 백그라운드에서 위치 추적이 실제로 켜졌는지 5초 뒤 확인
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            let count = location.receivedCount
            log(count > 0
                ? "⚡️ 단축어 실험: 위치 추적 켜짐 — 위치 수신 \(count)회"
                : "⚡️ 단축어 실험: 5초 동안 위치 수신 0회 — 백그라운드에서 시작이 막혔을 수 있어요 (권한 \(location.authorizationText))")
        }
    }

    /// 남아 있는 카드 중 이어받을 것 1개(가장 최근 것 = 목록의 마지막 활성 카드)와 종료할 나머지
    private static func pickActivityToAdopt() -> (keep: Activity<LyricsActivityAttributes>?, others: [Activity<LyricsActivityAttributes>]) {
        let all = Activity<LyricsActivityAttributes>.activities
        let keep = all.last { $0.activityState == .active }
        return (keep, all.filter { $0.id != keep?.id })
    }

    /// 앱이 새로 시작됐을 때: 남아 있는 카드를 이어받아 추적 재개 (나머지는 종료)
    /// 로그인이 안 돼 있거나 사용자가 정지해 둔 상태면 남은 카드를 모두 종료
    private func adoptExistingActivities() {
        let (keep, others) = Self.pickActivityToAdopt()
        let total = (keep == nil ? 0 : 1) + others.count
        guard total > 0 else { return }

        guard let keep, auth.isLoggedIn, !userStopped else {
            Task { for old in Activity<LyricsActivityAttributes>.activities { await old.end(nil, dismissalPolicy: .immediate) } }
            log("🧹 남은 카드 \(total)개 종료 (\(auth.isLoggedIn ? "사용자가 정지해 둠" : "로그인 안 됨"))")
            return
        }
        if !others.isEmpty { Task { for old in others { await old.end(nil, dismissalPolicy: .immediate) } } }
        log("♻️ 기존 카드 이어받음 (\(total)개 중 1개, 나머지 종료)")
        beginTracking(adopting: keep)
    }

    // MARK: - 조회 결과 → 잠금화면 카드

    private func didUpdate(_ np: NowPlaying?, trackChanged: Bool) {
        // 조회 사이가 너무 벌어졌다면 앱이 중단됐다가 깨어난 것 (위치 추적을 끈 뒤 실제로 중단되는지 확인용)
        let now = Date()
        if let last = lastPollAt, now.timeIntervalSince(last) > 40 {   // 일시정지 중 정상 간격이 15초라 여유를 둠
            log("💓 조회 재개 — \(Self.durationText(now.timeIntervalSince(last))) 만에 · \(appStateName()) · 위치 \(location.isRunning ? "ON" : "OFF")")
        }
        lastPollAt = now

        // SDK 연결 시점 3: 재생 중인데 SDK가 끊겨 있으면 60초에 1번까지 다시 연결 시도 (작업 025, 009 재확인용)
        if np?.isPlaying == true, isRunning, UIApplication.shared.applicationState != .active {
            tryRemoteConnect(foreground: false)
        }

        guard activity != nil else { return }
        updateLocationPolicy(playing: np?.isPlaying == true)

        // 안내 문구가 떠 있는 동안에는 재생이 다시 시작되기 전까지 폴링이 카드를 덮어쓰지 않음
        if np?.isPlaying != true, idleNoticeShown || (noticeUntil.map { Date() < $0 } ?? false) {
            skippedUpdates += 1
            return
        }

        // 곡이 바뀌면 새 가사를 찾음
        if np?.key != lyricsKey {
            if let np { loadLyrics(for: np) } else { resetLyrics() }
        } else if let np, np.isPlaying, lyricsSettledKey == np.key {
            // 일시정지 상태로 처음 본 곡을 재생하기 시작했으면 그때 다음 곡 미리 받기 (곡당 1번은 안에서 막음, 작업 021 리뷰)
            startPrefetchIfNeeded(after: np.key)
        }

        let state = makeState(np)
        if let reason = updateReason(new: state, key: np?.key) {
            sendCard(state, key: np?.key, reason: reason)
        } else {
            skippedUpdates += 1   // 바뀐 게 없으면 카드를 건드리지 않음
        }
        scheduleNextLine()
    }

    // MARK: - 위치 추적은 재생 중일 때만

    /// 재생 중이면 위치 추적을 켜 두고, 멈춘 지 idleGrace초가 지나면 끔.
    /// ⚠️ 끄면 앱이 곧 일시 중단돼서, 그 뒤 재생을 다시 시작해도 앱 화면을 열기 전까지는 카드가 갱신되지 않아요.
    private func updateLocationPolicy(playing: Bool) {
        guard isRunning else { return }
        if playing {
            idleTask?.cancel()
            idleTask = nil
            idleNoticeShown = false   // 재생이 다시 시작됐으니 안내 문구를 걷고 일반 카드로 복귀
            noticeUntil = nil
            if !location.isRunning {
                log("📍 재생 재개 → 위치 추적 다시 켬")
                _ = location.start()
            }
        } else if location.isRunning, idleTask == nil {
            let minutes = Int(idleGrace / 60)
            log("⏸ 재생 멈춤 → \(minutes)분 뒤에도 멈춰 있으면 위치 추적을 끔")
            idleTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(idleGrace * 1_000_000_000))
                guard !Task.isCancelled else { return }
                idleTask = nil
                // 끈 뒤에는 카드를 갱신할 수 없으므로, 끄기 직전에 "▶︎를 누르면 가사가 다시 나와요"로 바꿔 둠
                await showIdleNotice()
                location.stop()
                log("🔋 \(minutes)분 동안 재생이 없어 위치 추적을 껐어요 (카드의 ▶︎ 버튼이나 앱 화면으로 다시 켤 수 있어요)")
            }
        }
    }

    // MARK: - Spotify 호출 한도 차단 (작업 008)

    /// 호출 한도(429)로 60초를 넘게 막혔을 때(또는 이미 막혀 있는 걸 알았을 때) 한 번만 처리
    /// 카드를 "마지막 곡 일시정지 + 조회 한도 초과 · 재개 시각" 안내로 바꾸고(끄기 전에 먼저 갱신), 위치 추적을 끔 (조회를 못 하니 배터리 절약)
    /// body가 있으면 방금 429를 받은 것 → 오늘 호출 수와 응답 본문을 로그에 남김
    private func handleQuotaBlock(until: Date, body: String?) {
        if let body {
            log("⛔️ 한도 초과 — 오늘 호출 \(APIUsage.total(daysAgo: 0))회째 (\(APIUsage.summary(daysAgo: 0)))")
            log("⛔️ 응답: \(body.isEmpty ? "(본문 없음)" : body)")
        }
        let untilText = SpotifyBlock.untilText(until)
        let notice = "Spotify 조회 한도 초과 · \(untilText) 이후 재개"
        let firstTime = quotaNoticeText == nil
        quotaNoticeText = notice
        if firstTime {
            log("⛔️ 한도 차단 — \(untilText) 이후 재개 (그때까지 Spotify를 호출하지 않아요)")
            readiness.refresh()
            lineTask?.cancel()
            idleTask?.cancel()
            idleTask = nil
        }
        guard activity != nil else { return }
        // 카드부터 갱신하고, 끝난 뒤에 위치 추적을 끔
        let sent = sendCard(makeState(nowPlaying.current), key: nowPlaying.current?.key, reason: "한도 차단 안내")
        guard firstTime, location.isRunning else { return }
        Task {
            await sent?.value
            location.stop()
            log("🔋 한도 차단 중이라 위치 추적을 껐어요")
        }
    }

    /// 한도 차단 재개 시각이 지났으면(앱 열기·▶︎·단축어 때) 안내를 걷고 조회·위치 추적을 다시 시작
    private func resumeAfterQuotaBlockIfExpired() {
        guard quotaNoticeText != nil, SpotifyBlock.until == nil else { return }
        SpotifyBlock.clear()
        quotaNoticeText = nil
        log("✅ 한도 차단이 풀렸어요 — 조회를 다시 시작해요")
        readiness.refresh()
        guard isRunning else { return }
        if !location.isRunning { _ = location.start() }
        nowPlaying.start()
        // 안내 카드를 바로 일반 카드로 되돌리려면 곧 오는 조회 결과를 기다리면 됨 (조회는 start()가 바로 시작)
    }

    /// 위치 추적을 끄기 직전의 카드: ⏸ 일시정지 · 다시 재생했다면 ▶︎를 눌러 주세요
    /// (Spotify에서 직접 다시 재생한 경우에도 카드는 따라오지 않아서, 그때도 ▶︎를 누르면 된다는 뜻)
    private func showIdleNotice() async {
        guard activity != nil else { return }
        var state = makeState(nowPlaying.current)
        state.previous = ""
        state.current = "⏸ 일시정지"
        state.next = "다시 재생했다면 ▶︎를 눌러 주세요"
        idleNoticeShown = true
        await sendCard(state, key: nowPlaying.current?.key, reason: "위치 추적 끄기 직전 안내")?.value
    }

    // MARK: - 카드의 ▶︎ "가사 다시 켜기" 버튼 (작업 001)

    /// 카드 버튼 → iOS가 앱을 깨우고 호출. 재생 요청 · 위치 추적 재시작 · 즉시 조회 · 폴링 재개를 한 번에 함
    /// 인텐트 실행 시간이 짧아서, 재생 요청(실패 시 재시도 포함)은 따로 진행시키고 기다리지 않음 →
    /// 위치 추적 재시작·폴링 재개·가사 재연결이 재생 요청 재시도에 막히지 않음
    func resumeFromCard() async {
        log("▶︎ 카드 버튼 눌림 — 앱 상태: \(appStateName()) · 위치 권한: \(location.authorizationText) · 위치 추적 \(location.isRunning ? "ON" : "OFF")")
        resumeAfterQuotaBlockIfExpired()
        guard isRunning, activity != nil else {
            log("⚠️ 추적이 꺼져 있어요 (이어받을 카드가 없거나 로그인이 안 된 상태) → 앱 화면을 열어 [시작]을 눌러 주세요")
            return
        }
        // 한도 차단 중이면 API를 호출하지 않고 카드 안내만 다시 표시
        if let until = SpotifyBlock.until {
            log("⛔️ 한도 차단 중 — \(SpotifyBlock.untilText(until)) 이후 재개")
            handleQuotaBlock(until: until, body: nil)
            return
        }
        idleTask?.cancel()
        idleTask = nil

        // 1) 재생 요청(따로 진행)과 위치 추적 시작
        //    재생 요청(재시도 포함)이 이미 진행 중이면 새로 시작하지 않음 (▶︎를 연달아 누르거나 인텐트가 겹칠 때 요청·카드 문구가 뒤섞이지 않게).
        //    위치 추적 재시작·가사 재연결은 그대로 진행
        if playRequestInProgress {
            log("⏳ 재생 요청 진행 중 — 이번 ▶︎는 가사만 다시 연결")
        } else {
            playRequestInProgress = true   // 같은 메인 액터에서 바로 표시해야 겹쳐 호출돼도 한 번만 시작됨
            Task {
                await requestPlay()
                playRequestInProgress = false
            }
        }
        restartLocationForResume()

        // 2) 폴링 재개 + 1초 뒤 즉시 1회 조회 (Spotify가 재생 상태를 반영할 시간을 잠깐 줌)
        nowPlaying.start()
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        await nowPlaying.refreshNow()
        log("▶︎ 카드 버튼 처리 끝 — 재생: \(nowPlaying.current?.isPlaying == true ? "예" : "아니오") · 위치 추적 \(location.isRunning ? "ON" : "OFF")")

        startAfterPlayLog()
    }

    /// ▶︎ 이후 10분 동안 1분마다 한 줄 (잠근 채 장시간 갱신이 이어지는지 사용자가 판단하는 용도). 10분 뒤 중단
    /// 앱이 중단됐다가 깨어나 정해진 시각보다 늦게 찍히면 그 사실을 같이 적음
    private func startAfterPlayLog() {
        afterPlayTask?.cancel()
        let start = Date()
        afterPlayTask = Task {
            for minute in 1...10 {
                let target = start.addingTimeInterval(TimeInterval(minute * 60))
                let wait = target.timeIntervalSinceNow
                if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
                guard !Task.isCancelled else { return }
                let late = Date().timeIntervalSince(target)
                var line = "🕐 ▶︎ 후 \(minute)분 · \(appStateName()) · 위치 \(location.isRunning ? "ON" : "OFF") · 조회 #\(nowPlaying.pollCount)"
                if late > 10 { line += " · ⚠️ \(Int(late))초 늦게 (그 사이 앱이 중단됐을 수 있어요)" }
                log(line)
            }
        }
    }

    private enum PlayResult {
        case done          // 재생 요청 성공 (또는 이미 재생 중이라 가사만 다시 연결하면 되는 경우)
        case noDevices     // 404이고 연결된 기기 목록이 비어 있음 → 다시 시도해 볼 만함
        case openSpotify   // 404인데 옮길 기기가 없거나 이전이 실패 → Spotify 앱을 열어야 함
        case other         // 그 밖의 실패 (로그만 남김)
    }

    /// Spotify 재생 요청. 이미 재생 중이어도 문제없이 가사만 다시 연결되도록 실패해도 멈추지 않음
    /// 404이고 기기 목록이 비어 있으면(Spotify 앱이 연결을 잠깐 끊었을 수 있음) 3초 간격으로 최대 2회 처음부터 다시 시도하고,
    /// 모두 실패하면 카드에 "Spotify 앱을 한 번 열어 주세요"를 띄움
    private func requestPlay() async {
        var result = await playOnce()
        var attempt = 0
        while result == .noDevices, attempt < 2 {
            attempt += 1
            showTemporaryNotice("Spotify에 연결하는 중…")
            log("🔁 재생 요청 재시도 \(attempt)/2 (3초 뒤)")
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            result = await playOnce()
            log(result == .done ? "🔁 재생 요청 재시도 \(attempt)/2 성공" : "🔁 재생 요청 재시도 \(attempt)/2 실패")
        }
        if result == .noDevices || result == .openSpotify {
            showTemporaryNotice("Spotify 앱을 한 번 열어 주세요")
        }
    }

    /// 재생 요청 1번: 마지막으로 재생이 확인된 기기(`device_id`)로 요청하고, 404면 기기 목록을 로그에 남기고 재생을 옮겨 재시도
    /// device를 주면 그 기기로 요청 (카드 탭 후 나타난 기기, 작업 010)
    private func playOnce(device: SpotifyDevice? = nil) async -> PlayResult {
        let remembered = device ?? nowPlaying.lastDevice
        let target = remembered.map { "기기: \($0.name)" } ?? "기기 지정 없음"
        do {
            let status = try await api.play(deviceID: remembered?.id)
            log("▶︎ Spotify 재생 요청 성공 (HTTP \(status), \(target))")
            return .done
        } catch SpotifyAPIError.blocked(let until, let body) {
            handleQuotaBlock(until: until, body: body)
            return .other
        } catch SpotifyAPIError.http(let code, let body) {
            log("⚠️ Spotify 재생 요청 실패 (HTTP \(code), \(target)): \(body)")
            if code == 404 { return await recoverNoActiveDevice(remembered: remembered) }
            if code == 403, body.localizedCaseInsensitiveContains("scope") {
                log("⚠️ 재생 제어 권한이 없어요 → 로그아웃 후 Spotify에 다시 로그인")
                showTemporaryNotice("Spotify에 다시 로그인해 주세요")
                return .other
            }
            if code == 403 {
                log("ℹ️ 이미 재생 중이거나 지금은 재생 명령을 받을 수 없는 상태 — 가사만 다시 연결해요")
                return .done
            }
            return .other
        } catch {
            log("⚠️ Spotify 재생 요청 오류: \(error.localizedDescription)")
            return .other
        }
    }

    /// 404 NO_ACTIVE_DEVICE 대응: 기기 목록을 로그에 남기고, 기억한 기기 또는 스마트폰 기기로 재생을 옮겨 재시도
    private func recoverNoActiveDevice(remembered: SpotifyDevice?) async -> PlayResult {
        let devices: [SpotifyDevice]
        do {
            devices = try await api.devices()
        } catch SpotifyAPIError.blocked(let until, let body) {
            handleQuotaBlock(until: until, body: body)
            return .other
        } catch {
            log("⚠️ 기기 목록 조회 오류: \(error.localizedDescription)")
            return .openSpotify
        }

        if devices.isEmpty {
            log("❌ 연결된 Spotify 기기가 없어요 — Spotify 앱이 연결을 끊었음 (Spotify 앱을 직접 열어야 다시 연결돼요)")
            return .noDevices
        }
        for device in devices {
            log("🔌 기기: \(device.name) · \(device.type) · 활성 \(device.isActive ? "예" : "아니오")")
        }

        // 기억한 기기가 목록에 있으면 그것, 없으면 스마트폰 기기. 컴퓨터·스피커 등으로 멋대로 옮기지는 않음
        let target = devices.first { $0.id != nil && $0.id == remembered?.id }
            ?? devices.first { $0.type == "Smartphone" && $0.id != nil }
        guard let target, let targetID = target.id else {
            log("❌ 재생을 옮길 기기를 찾지 못했어요 (기억한 기기: \(remembered?.name ?? "없음"))")
            return .openSpotify
        }

        do {
            let status = try await api.transferPlayback(to: targetID, play: true)
            log("▶︎ 재생 기기 이전 성공 (HTTP \(status)) → \(target.name)")
            return .done
        } catch SpotifyAPIError.blocked(let until, let body) {
            handleQuotaBlock(until: until, body: body)
            return .other
        } catch {
            log("❌ 재생 기기 이전 실패 → \(target.name): \(error.localizedDescription)")
            return .openSpotify
        }
    }

    /// 위치 추적 재시작. 백그라운드에서 새로 시작이 막힐 수 있어서(권한 "앱 사용 중") 5초 뒤 수신 여부까지 기록
    private func restartLocationForResume() {
        if location.isRunning {
            log("📍 위치 추적이 이미 켜져 있어요")
            return
        }
        guard location.start() else {
            log("❌ 위치 추적 재시작 실패 — 권한: \(location.authorizationText)")
            return
        }
        log("📍 위치 추적 재시작 요청 (앱 상태: \(appStateName()), 권한: \(location.authorizationText)) — 5초 뒤 수신 여부 확인")
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            let count = location.receivedCount
            log(count > 0
                ? "✅ 위치 추적 재시작 성공 — 위치 수신 \(count)회"
                : "❌ 위치 추적 재시작 후 5초 동안 위치 수신 0회 — 백그라운드에서 시작이 막혔을 수 있어요 (권한 \(location.authorizationText))")
        }
    }

    /// 몇 초 동안 카드에 짧은 안내를 띄움 (그 사이 폴링이 덮어쓰지 않음)
    private func showTemporaryNotice(_ text: String) {
        guard activity != nil else { return }
        var state = makeState(nowPlaying.current)
        state.previous = ""
        state.current = text
        state.next = ""
        noticeUntil = Date().addingTimeInterval(8)
        sendCard(state, key: nowPlaying.current?.key, reason: "안내: \(text)")
    }

    // MARK: - 카드 탭 → Spotify 열기 → 자동 재생 (작업 009·010)

    private var spotifyWaitTask: Task<Void, Never>?   // Spotify를 연 뒤 기기가 나타나길 기다리는 중 (하나만)

    /// 앱 주소(livelyrics://…)로 앱이 열렸을 때. open-spotify = 잠금화면 카드 탭
    func handleOpenURL(_ url: URL) {
        guard url.scheme == SpotifyConfig.callbackScheme else { return }
        if url.host == "open-spotify" {
            openSpotify()
        } else {
            log("ℹ️ 알 수 없는 앱 주소: \(url.absoluteString)")
        }
    }

    private func openSpotify() {
        log("🔗 카드 탭 → Spotify 열기")
        guard let url = URL(string: "spotify:"), UIApplication.shared.canOpenURL(url) else {
            log("⚠️ Spotify 앱을 열 수 없어요 (설치돼 있지 않음)")
            return
        }
        // Spotify로 넘어가면 우리 앱은 백그라운드가 됨 → 기다리는 동안 살아 있도록 화면에 있는 지금 위치 추적부터 켬
        let shouldWait = isRunning && activity != nil && SpotifyBlock.until == nil   // 한도 차단 중이면 대기 안 함 (작업 008)
        if shouldWait, spotifyWaitTask == nil { restartLocationForResume() }
        UIApplication.shared.open(url)
        if shouldWait { startSpotifyWait() }
    }

    /// Spotify를 연 직후: 2초마다 기기 목록을 확인(최대 20초)하고, 기기가 나타나면 그 기기로 재생 요청 1번
    /// 오래 멈춘 뒤에는 Spotify 앱이 연결을 끊어서(404) 사용자가 Spotify에서 재생을 직접 눌러야 했던 것을 대신함
    private func startSpotifyWait() {
        guard spotifyWaitTask == nil else {
            log("🔗 이미 연결 대기 중 — 이어서 기다려요")
            return
        }
        idleTask?.cancel()
        idleTask = nil
        log("🔗 Spotify 열림 → 연결 대기 (최대 20초)")
        spotifyWaitTask = Task {
            await waitForSpotifyDeviceAndPlay()
            spotifyWaitTask = nil
        }
    }

    private func waitForSpotifyDeviceAndPlay() async {
        let interval: UInt64 = 2
        for step in 1...10 {
            try? await Task.sleep(nanoseconds: interval * 1_000_000_000)
            guard !Task.isCancelled, isRunning else { return }
            let elapsed = Int(interval) * step

            // 폴링이 이미 재생 중을 확인했으면 재생 요청을 보내지 않음
            if nowPlaying.current?.isPlaying == true {
                log("🔗 이미 재생 중 → 대기 종료")
                return
            }

            let devices: [SpotifyDevice]
            do {
                devices = try await api.devices()
            } catch SpotifyAPIError.blocked(let until, let body) {
                handleQuotaBlock(until: until, body: body)
                return
            } catch {
                log("⚠️ 기기 목록 조회 오류: \(error.localizedDescription)")
                continue
            }

            // 기억한 기기, 없으면 스마트폰 기기 (컴퓨터·스피커 등으로는 옮기지 않음 — 기존 404 대응과 같은 기준)
            let remembered = nowPlaying.lastDevice
            guard let target = devices.first(where: { $0.id != nil && $0.id == remembered?.id })
                    ?? devices.first(where: { $0.type == "Smartphone" && $0.id != nil }) else { continue }

            // 활성 기기면 이미 재생 중일 수 있어서 한 번 조회해서 확인 (활성이어도 일시정지일 수 있음)
            if target.isActive {
                await nowPlaying.refreshNow()
                if nowPlaying.current?.isPlaying == true {
                    log("🔗 이미 재생 중 → 대기 종료")
                    return
                }
            }

            // ▶︎ 버튼의 재생 요청이 진행 중이면 겹쳐 보내지 않음
            guard !playRequestInProgress else {
                log("🔗 기기 나타남 (\(elapsed)초) — ▶︎ 재생 요청이 진행 중이라 대기 종료")
                return
            }
            log("🔗 기기 나타남 (\(elapsed)초) → 재생 요청")
            playRequestInProgress = true
            _ = await playOnce(device: target)
            playRequestInProgress = false

            // 재생 요청 뒤 즉시 1회 조회 → 카드·가사 갱신 (▶︎ 흐름과 같은 순서)
            if !location.isRunning { restartLocationForResume() }
            nowPlaying.start()
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await nowPlaying.refreshNow()
            return
        }
        log("🔗 20초 동안 기기 없음 → 대기 종료")
    }

    // MARK: - 가사

    private func resetLyrics() {
        lyricsTask?.cancel()
        lineTask?.cancel()
        lyrics = []
        lyricsKind = .none
        lyricsKey = nil
        lyricsSettledKey = nil
    }

    /// 이 곡(key)의 가사 처리가 끝남 → 재생 중이면 다음 곡 미리 받기 (재생 중이 아니면 재생이 시작될 때 didUpdate가 다시 부름)
    private func lyricsSettled(_ key: String) {
        lyricsSettledKey = key
        startPrefetchIfNeeded(after: key)
    }

    /// 곡이 바뀔 때 1번만 조회. 저장된 싱크 가사는 바로 적용하고, 없으면 Task에서 검색 (작업 021)
    private func loadLyrics(for np: NowPlaying) {
        resetLyrics()
        lyricsKey = np.key
        let key = np.key

        // 제목만 봐도 연주곡이면 검색·기록 없이 바로 연주곡 처리 (카드는 호출한 쪽이 이어서 갱신함)
        if InstrumentalTitle.matches(np.title) {
            lyricsKind = .instrumental
            log("🎼 연주곡 (제목으로 판단): \(np.title)")
            lyricsSettled(key)
            return
        }

        // 저장해 둔 싱크 가사는 바로 적용 → 호출한 didUpdate의 첫 갱신("곡 변경")에 가사가 같이 들어감 (작업 021)
        if let saved = LyricsStore.loadSynced(title: np.title, artist: np.artist) {
            apply(saved, for: np, save: false)
            log("💾 저장된 싱크 가사 사용 (\(saved.lines.count)줄)")
            lyricsSettled(key)
            return
        }

        // 이 곡을 미리 받는 중이면(앞선 어느 곡에서 시작했든) 새로 검색하지 않고 그 작업이 끝나길 기다림 (작업 021)
        let pending = prefetchingKeys[key].flatMap { prefetchTasks[$0] }
        if pending != nil { log("⏳ 미리 받는 중인 가사를 기다려요: \(np.artist) - \(np.title)") }

        lyricsTask = Task {
            var result: LyricsResult?
            var fromNetwork = false

            if let pending {
                await pending.value
                guard !Task.isCancelled, lyricsKey == key else { return }
            }

            if pending != nil, let saved = LyricsStore.loadSynced(title: np.title, artist: np.artist) {
                // 기다린 미리 받기가 방금 싱크 가사를 저장했으면 인터넷 조회 없이 사용 (기다리지 않았으면 위에서 이미 확인함)
                result = saved
                log("💾 저장된 싱크 가사 사용 (\(saved.lines.count)줄)")
            } else if let skipped = resultFromSearchRecord(for: np) {
                // 최근에 이미 검색했다면(간격 안) 인터넷 조회를 건너뜀
                result = skipped
            } else {
                log("🔎 가사 검색: \(np.artist) - \(np.title)")
                result = await searchWithRetry(np, key: key)
                guard !Task.isCancelled, lyricsKey == key else { return }
                fromNetwork = result != nil
                // 인터넷 조회가 끝내 실패했으면 예전에 저장해 둔 일반 가사라도 사용
                if result == nil, let savedPlain = LyricsStore.loadPlain(title: np.title, artist: np.artist) {
                    result = savedPlain
                    log("💾 저장된 일반 가사 사용 (싱크 가사 없음)")
                }
            }
            guard !Task.isCancelled, lyricsKey == key else { return }

            if let result { apply(result, for: np, save: fromNetwork) }

            // 가사가 도착하면 바로 카드에 반영
            if let current = nowPlaying.current, current.key == key {
                let reason: String
                switch lyricsKind {
                case .synced: reason = "가사 도착"
                case .plain: reason = "싱크 가사 없음 (일반 가사만)"
                case .instrumental: reason = "연주곡"
                case .none: reason = "가사 없음"
                }
                sendCard(makeState(current), key: key, reason: reason)
                scheduleNextLine()
            }
            lyricsSettled(key)
        }
    }

    // MARK: - 다음 곡 가사 미리 받기 (작업 021)

    /// 현재 곡(key)의 가사 처리가 끝난 뒤 1번: 재생 중이고 카드가 있으면 대기열 다음 곡의 가사를 미리 받아 저장
    /// 곡당 1번만 (prefetchStartedFor). 일시정지 상태로 처음 본 곡은 재생이 시작될 때 didUpdate가 다시 부름
    /// 앞서 시작한 미리 받기(다른 곡)가 아직 진행 중이어도 취소하지 않음 — 그 결과는 저장만 됨
    private func startPrefetchIfNeeded(after key: String) {
        guard isRunning, activity != nil, lyricsKey == key, prefetchStartedFor != key,
              let current = nowPlaying.current, current.key == key, current.isPlaying else { return }
        prefetchStartedFor = key
        prefetchID += 1
        let id = prefetchID
        prefetchTasks[id] = Task {
            await prefetchNext(currentKey: key, id: id)
            prefetchTasks[id] = nil
            prefetchingKeys = prefetchingKeys.filter { $0.value != id }
        }
    }

    /// 정지할 때: 진행 중인 미리 받기를 모두 취소하고 상태를 비움 (정지 뒤 Spotify·LRCLIB 호출 방지, 작업 021 리뷰)
    private func cancelPrefetches() {
        for task in prefetchTasks.values { task.cancel() }
        prefetchTasks = [:]
        prefetchingKeys = [:]
        prefetchStartedFor = nil
    }

    /// 미리 받기를 시도한 곡 목록에서 뺌 (검색하지 못했으면 다음에 다시 미리 받을 수 있게)
    private func forgetPrefetched(_ key: String) {
        prefetchedKeys.removeAll { $0 == key }
    }

    /// 대기열 다음 곡 1곡의 가사를 LRCLIB에서 받아 저장·검색 기록만 남김 (현재 곡 상태·카드는 건드리지 않음)
    /// 실패·한도 차단이어도 재시도하지 않음 (429·한도 차단 처리는 폴링 쪽이 함)
    private func prefetchNext(currentKey: String, id: Int) async {
        let next: QueuedTrack?
        do {
            next = try await api.nextInQueue()
        } catch SpotifyAPIError.blocked(let until, let body) {
            log("⚠️ 다음 곡 미리 받기 실패: Spotify 한도 차단 중")
            // 대기열 조회가 처음으로 큰 429를 맞았으면(body 있음) 폴링과 같은 한도 차단 처리 (호출 수·응답 본문 로그, 카드 안내)
            if body != nil { handleQuotaBlock(until: until, body: body) }
            return
        } catch SpotifyAPIError.rateLimited {
            log("⚠️ 다음 곡 미리 받기 실패: Spotify 호출 한도 초과")
            return
        } catch {
            if Task.isCancelled { return }   // 정지로 취소됨
            log("⚠️ 다음 곡 미리 받기 실패: 다음 곡 조회 오류 — \(error.localizedDescription)")
            return
        }
        guard !Task.isCancelled else { return }   // 정지됨 → 검색하지 않음
        guard let next else {
            log("⏭ 다음 곡 미리 받기 생략 — 대기열에 다음 곡이 없거나 곡이 아님")
            return
        }
        // 대기열 조회 사이에 그 곡이 이미 재생돼 loadLyrics가 맡았으면 이중 검색하지 않음 (작업 021 리뷰)
        guard next.key != lyricsKey,
              LyricsPrefetch.shouldPrefetch(nextKey: next.key, currentKey: currentKey, tried: Set(prefetchedKeys)) else { return }
        prefetchedKeys.append(next.key)
        if prefetchedKeys.count > LyricsPrefetch.memory {
            prefetchedKeys.removeFirst(prefetchedKeys.count - LyricsPrefetch.memory)
        }
        prefetchingKeys[next.key] = id   // 이 곡이 재생되면 loadLyrics가 이 작업을 기다림

        // 검색할 필요가 없는 곡: 연주곡 제목, 저장된 싱크 가사, 신선한 검색 기록
        if InstrumentalTitle.matches(next.title)
            || LyricsStore.loadSynced(title: next.title, artist: next.artist) != nil
            || freshSearchRecord(title: next.title, artist: next.artist) != nil {
            return
        }

        let result: LyricsResult
        do {
            result = try await LyricsService.find(
                title: next.title, artist: next.artist, album: next.album, duration: next.duration, fast: false)
        } catch {
            forgetPrefetched(next.key)   // 검색하지 못한 곡은 다음에 다시 미리 받을 수 있게 (재시도는 하지 않음)
            if Task.isCancelled { return }   // 정지로 취소됨
            log("⚠️ 다음 곡 미리 받기 실패: \(next.artist) - \(next.title) — \(error.localizedDescription)")
            return
        }
        store(result, title: next.title, artist: next.artist, album: next.album, duration: next.duration)
        let found: String
        switch result.kind {
        case .synced: found = "싱크 \(result.lines.count)줄"
        case .plain: found = "일반 가사만"
        case .instrumental, .none: found = "없음"
        }
        log("⏭ 다음 곡 가사 미리 받음: \(next.artist) - \(next.title) (\(found))")
    }

    /// 재검색 간격 (작업 005): 일반 가사만·못 찾음은 24시간, LRCLIB이 연주곡이라고 한 곡은 30일 안에는 다시 검색하지 않음
    /// 싱크 가사는 저장본을 쓰므로 여기서 다루지 않음. 간격이 지났거나 기록이 없으면 nil (= 검색해야 함)
    private func resultFromSearchRecord(for np: NowPlaying) -> LyricsResult? {
        guard let found = freshSearchRecord(title: np.title, artist: np.artist) else { return nil }
        log("⏭ 가사 검색 생략 — \(found.1)")
        return found.0
    }

    /// 재검색 간격 안의 검색 기록이 있으면 (쓸 결과, 로그용 설명). 로그는 남기지 않음 (미리 받기도 같은 기준을 씀, 작업 021)
    private func freshSearchRecord(title: String, artist: String) -> (LyricsResult, String)? {
        guard let record = LyricsStore.searchRecord(title: title, artist: artist) else { return nil }
        let day: TimeInterval = 24 * 3600
        switch record.result {
        case "plain":
            // 저장해 둔 일반 가사 파일이 있을 때만 건너뜀
            guard record.isFresh(within: day), let saved = LyricsStore.loadPlain(title: title, artist: artist) else { return nil }
            return (saved, "일반 가사만 기록 (\(record.agoText))")
        case "none":
            guard record.isFresh(within: day) else { return nil }
            return (LyricsResult(kind: .none), "못 찾음 기록 (\(record.agoText))")
        default:
            // 예전 버전이 "연주곡"으로 기록해 둔 곡도 여기로 와서 다시 검색함 (LRCLIB의 연주곡 표시는 믿지 않음)
            return nil
        }
    }

    /// LRCLIB 검색. 일시 오류(서버 5xx·429·네트워크)면 2·5·15·30·60초 간격으로 최대 6번 시도 (작업 012).
    /// 일시 오류가 아니면 바로 멈춤. 끝내 실패하면 nil
    private func searchWithRetry(_ np: NowPlaying, key: String) async -> LyricsResult? {
        var failures = 0
        while true {
            do {
                // 지금 재생 중인 곡이라 1·2단계를 동시에 보냄 (작업 021)
                return try await LyricsService.find(
                    title: np.title, artist: np.artist, album: np.album, duration: np.duration, fast: true)
            } catch {
                guard !Task.isCancelled, lyricsKey == key else { return nil }
                failures += 1
                guard LyricsRetryPolicy.isTransient(error) else {
                    log("⚠️ 가사 조회 실패 (재시도 안 함): \(error.localizedDescription)")
                    return nil
                }
                guard let wait = LyricsRetryPolicy.delay(afterFailure: failures) else {
                    log("⚠️ 가사 조회 실패 (\(failures)번 시도): \(error.localizedDescription)")
                    return nil
                }
                log("⚠️ 가사 조회 오류: \(error.localizedDescription) — \(Int(wait))초 뒤 재시도")
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                guard !Task.isCancelled, lyricsKey == key else { return nil }
            }
        }
    }

    /// 찾은 가사를 현재 곡에 적용하고, 인터넷에서 새로 받은 것이면 앱 전용 폴더에 저장
    private func apply(_ result: LyricsResult, for np: NowPlaying, save: Bool) {
        lyricsKind = result.kind
        lyrics = result.kind == .synced ? result.lines : []

        if save {
            switch result.kind {
            case .synced:
                log("🎵 가사 찾음 (\(result.stage)단계: \(result.stageName), 싱크 \(result.lines.count)줄)")
            case .plain:
                log("🎵 가사 찾음 (\(result.stage)단계: \(result.stageName), 일반 가사만 — 싱크 없음)")
            case .instrumental:
                log("🎼 연주곡으로 등록된 곡이에요")
            case .none:
                log("⚠️ 가사 없음: \(np.title) – \(np.artist)")
            }
            if let folder = store(result, title: np.title, artist: np.artist, album: np.album, duration: np.duration) {
                log("💾 가사 저장 → LiveLyrics/\(folder)/")
            }
        }
    }

    /// 인터넷에서 받은 가사를 앱 전용 폴더에 저장하고 검색 기록을 남김. 현재 곡 상태는 바꾸지 않음 (미리 받기도 씀, 작업 021)
    /// 저장했으면 폴더 이름("synced"/"plain")
    @discardableResult
    private func store(_ result: LyricsResult, title: String, artist: String, album: String, duration: TimeInterval) -> String? {
        var folder: String?
        do {
            folder = try LyricsStore.save(result, title: title, artist: artist)
        } catch {
            log("⚠️ 가사 저장 실패: \(error.localizedDescription)")
        }
        // 검색 결과를 곡별로 기록 (재검색 간격 · 못 찾은 곡 목록). 싱크 가사를 찾았으면 기록이 지워짐
        LyricsStore.updateSearchRecord(for: result, title: title, artist: artist, album: album, duration: duration)
        return folder
    }

    /// 다음 가사 줄이 나올 시각에 맞춰 카드 갱신 예약 (폴링 사이에 줄이 바뀌어도 제때 반영)
    private func scheduleNextLine() {
        lineTask?.cancel()
        guard activity != nil, quotaNoticeText == nil, !lyrics.isEmpty, let np = nowPlaying.current, np.isPlaying else { return }
        let position = min(np.duration, max(0, np.position() + syncOffset))
        // 다음 줄 시각과 카운트다운 숫자가 바뀌는 시각(작업 020) 중 먼저 오는 쪽에 깨어남
        let lineTime = LRCParser.context(lyrics, at: position).nextTime
        let countdownTime = LyricCountdown.nextChange(lyrics, at: position)   // lyrics는 싱크 가사일 때만 채워짐
        guard let nextTime = [lineTime, countdownTime].compactMap({ $0 }).min() else { return }
        let wait = max(0.05, nextTime - position)
        lineTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            guard !Task.isCancelled, let np = nowPlaying.current else { return }
            let state = makeState(np)
            if lastSent.map({ linesChanged($0, state) }) ?? true {
                sendCard(state, key: np.key, reason: "가사 줄 변경")
            }
            scheduleNextLine()
        }
    }

    /// 카드에 실제로 반영하고 로그를 남김
    /// 갱신이 끝날 때까지 기다려야 하면(예: 위치 추적을 끄기 직전) 돌려준 Task의 value를 await
    @discardableResult
    private func sendCard(_ state: LyricsActivityAttributes.ContentState, key: String?, reason: String) -> Task<Void, Never>? {
        guard let activity else { return nil }
        activityUpdates += 1
        lastSent = state
        lastSentKey = key
        // 가사 줄 변경은 줄마다 쌓이기만 해서 기록하지 않음 (횟수는 계속 셈, 작업 010)
        if reason != "가사 줄 변경" { log("🪪 카드 갱신 #\(activityUpdates) — \(reason)") }
        let content = ActivityContent(state: state, staleDate: nil)
        return Task { await activity.update(content) }
    }

    /// 카드 상태 변화(활성·종료·사라짐 등)를 로그로 남김 — 시작 직후 iOS가 카드를 어떻게 다루는지 확인용 (작업 019)
    private func watchActivityState(_ activity: Activity<LyricsActivityAttributes>) {
        activityStateTask?.cancel()
        log("🪪 카드 상태: \(activity.activityState)")
        activityStateTask = Task { [weak self] in
            for await state in activity.activityStateUpdates {
                guard !Task.isCancelled else { return }
                self?.log("🪪 카드 상태: \(state)")
            }
        }
    }

    /// 이전·현재·다음 줄 중 하나라도 달라졌는지 (같은 줄이 반복돼도 이전·다음 줄이 바뀌면 갱신)
    /// 카운트다운 숫자(3·2·1)가 바뀌어도 갱신 (작업 020)
    private func linesChanged(_ old: LyricsActivityAttributes.ContentState, _ new: LyricsActivityAttributes.ContentState) -> Bool {
        textChanged(old, new) || old.countdown != new.countdown
    }

    /// 이전·현재·다음 줄 글자만 비교
    private func textChanged(_ old: LyricsActivityAttributes.ContentState, _ new: LyricsActivityAttributes.ContentState) -> Bool {
        old.previous != new.previous || old.current != new.current || old.next != new.next
    }

    /// 카드를 갱신해야 하는 이유. 필요 없으면 nil
    private func updateReason(new: LyricsActivityAttributes.ContentState, key: String?) -> String? {
        guard let old = lastSent else { return "처음" }
        if key != lastSentKey { return "곡 변경" }
        if textChanged(old, new) { return "표시 내용 변경" }
        if old.isPlaying != new.isPlaying { return new.isPlaying ? "재생" : "일시정지" }
        // 숫자만 바뀐 건 줄 변경 예약과 같은 이유로 보내 로그를 늘리지 않음 (작업 020)
        if old.countdown != new.countdown { return "가사 줄 변경" }
        // 카드에 시간·진행 막대가 없으므로 시간 보정·일시정지 위치 이동은 보이지 않는 변화 → 갱신하지 않음 (작업 013)
        return nil
    }

    private func makeState(_ np: NowPlaying?) -> LyricsActivityAttributes.ContentState {
        guard let np else {
            var empty = ContentState(previous: "", current: nowPlaying.status, next: "Spotify에서 음악을 재생하세요")
            applyQuotaNotice(&empty)
            return empty
        }
        // 싱크 보정을 더한 위치 (곡 길이를 넘거나 0 미만이 되지 않게)
        let position = min(np.duration, max(0, np.position() + syncOffset))
        let start = Date().addingTimeInterval(-position)   // 곡의 0초 지점 = 지금 - 재생 위치
        // 가사 종류별 카드 내용
        //   싱크 가사   : 이전/현재/다음 줄
        //   일반 가사만 : "싱크 가사가 없어요" 안내 (일반 가사는 저장만 함)
        //   연주곡      : 🎼 연주곡
        //   못 찾음     : 아티스트/제목/앨범
        let info = "\(np.title) · \(np.artist)"
        let text: (previous: String, current: String, next: String, trackInfo: String)
        switch lyricsKind {
        case .synced:
            let lines = LRCParser.context(lyrics, at: position)
            text = (lines.previous, lines.current, lines.next, info)
        case .plain:
            text = ("", "싱크 가사가 없어요", "일반 가사만 있어서 저장해 뒀어요", info)
        case .instrumental:
            text = ("", "🎼 연주곡", "", info)
        case .none:
            text = (np.artist, np.title, np.album, "")
        }
        var state = ContentState(
            previous: text.previous,
            current: text.current,
            next: text.next,
            trackInfo: text.trackInfo,
            isPlaying: np.isPlaying,
            trackStart: start,
            trackEnd: start.addingTimeInterval(np.duration),
            pausedPosition: position,
            duration: np.duration
        )
        // 전주·간주 끝 3초의 3·2·1 (작업 020). 일시정지 중이면 0
        if lyricsKind == .synced, np.isPlaying {
            state.countdown = LyricCountdown.value(lyrics, at: position)
        }
        applyQuotaNotice(&state)
        return state
    }

    private typealias ContentState = LyricsActivityAttributes.ContentState

    /// 한도 차단 중이면 카드를 "마지막 곡 일시정지 + 안내 문구"로 덮어씀 (어떤 경로로 카드를 갱신해도 안내가 유지되게)
    private func applyQuotaNotice(_ state: inout ContentState) {
        guard let text = quotaNoticeText else { return }
        state.previous = ""
        state.current = text
        state.next = ""
        state.isPlaying = false
        state.countdown = 0   // 안내 중에는 숫자 숨김 (작업 020)
    }

    /// 295초 → "4분 55초", 42초 → "42초"
    private static func durationText(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return total >= 60 ? "\(total / 60)분 \(total % 60)초" : "\(total)초"
    }

    private func appStateName() -> String {
        switch UIApplication.shared.applicationState {
        case .active: return "앱 화면"
        case .inactive: return "전환 중"
        case .background: return "백그라운드"
        @unknown default: return "알 수 없음"
        }
    }

    // MARK: - Spotify iOS SDK 연결 (작업 025)

    /// 앱 화면으로 돌아왔을 때 (ContentView의 scenePhase .active). SDK 연결 시점 2
    func appBecameActive() {
        tryRemoteConnect(foreground: true)
    }

    /// SDK 연결 시도. foreground(추적 시작·화면 복귀)면 항상, 아니면 마지막 시도 후 60초가 지났을 때만 (RemoteRetry)
    private func tryRemoteConnect(foreground: Bool) {
        guard isRunning, auth.isLoggedIn, !remote.isConnected, !remote.isConnecting else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard RemoteRetry.shouldTry(now: now, lastAttempt: remoteLastAttempt, foreground: foreground) else { return }
        remoteLastAttempt = now
        remote.connect()
    }

    private func remoteConnectionChanged(_ connected: Bool) {
        nowPlaying.remoteConnected = connected
        if connected {
            remoteLastFailure = nil
            log("⚡ SDK 연결됨 — 폴링 완화(재생 중 \(Int(PollTiming.connectedPlaying))초)")
        } else {
            log("⚡ SDK 연결 끊김 — 3초 폴링 복귀 (\(remote.lastError ?? "이유 없음"))")
        }
    }

    /// 연결 실패 로그는 같은 이유가 연속이면 1번만
    private func remoteConnectFailed(_ reason: String) {
        guard reason != remoteLastFailure else { return }
        remoteLastFailure = reason
        log("⚡ SDK 연결 실패: \(reason) (\(appStateName()))")
    }

    // MARK: - 로그

    func log(_ message: String) {
        let time = Date().formatted(date: .omitted, time: .standard)
        let line = "\(time)  \(message)"
        print(line)
        logs.insert(line, at: 0)
        if logs.count > LogLimit.maxLines { logs = LogLimit.trimmed(logs) }
    }

    var logText: String { logs.reversed().joined(separator: "\n") }
}

// LogLimit(로그 보관 줄 수)은 Logic/LogLimit.swift로 옮김 (작업 024)
