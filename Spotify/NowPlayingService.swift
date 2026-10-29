// 앱 타깃 — Spotify를 주기적으로 조회하고, 그 사이 재생 위치는 직접 계산
//
// API는 몇 초마다만 물어보고, 사이 시간은 "마지막으로 받은 위치 + 경과 시간"으로 계산해요.
// 곡 변경·일시정지·위치 이동(seek)은 다음 조회 때 감지돼요.
// Spotify iOS SDK가 연결돼 있으면 SDK 이벤트(applyRemote)로 바로 감지하고, 폴링은 완화해요 (작업 025).
import Combine
import Foundation

struct NowPlaying: Equatable {
    var trackID: String
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval
    var isPlaying: Bool
    var progress: TimeInterval   // stamp 시점의 재생 위치(초)
    var stamp: TimeInterval      // 기기 가동 시간 기준 (시계 변경에 영향받지 않음)

    var key: String { trackID.isEmpty ? "\(artist)|\(title)" : trackID }

    /// 지금 재생 위치 (초)
    func position(at now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> TimeInterval {
        guard isPlaying else { return progress }
        return min(duration, max(0, estimatedPosition(at: now)))
    }

    /// 곡 끝까지 남은 시간(초). 곡 길이로 자르지 않아서 끝났으면 음수 (PollTiming.wait에 넘김, 작업 021)
    /// 재생 중이 아니거나 곡 길이를 모르면(0 이하) nil
    func remaining(at now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> TimeInterval? {
        guard isPlaying, duration > 0 else { return nil }
        return duration - estimatedPosition(at: now)
    }

    /// 마지막으로 받은 위치 + 경과 시간 (자르지 않은 값)
    private func estimatedPosition(at now: TimeInterval) -> TimeInterval {
        progress + (now - stamp)
    }
}

// PollTiming(곡 끝 무렵 조회 간격)은 LiveLyricsExperiment/Logic/PollTiming.swift로 옮김 (작업 024)

@MainActor
final class NowPlayingService: ObservableObject {
    @Published private(set) var current: NowPlaying?
    @Published private(set) var status = "대기 중"
    @Published private(set) var pollCount = 0
    /// 재생 중 조회 간격(초, SDK 미연결일 때). 개발자 메뉴에서 바꿀 수 있음. 나머지 간격은 PollTiming.interval (작업 008·025)
    @Published var interval: TimeInterval = PollTiming.interval(connected: false, state: .playing)

    /// Spotify iOS SDK 연결 여부 (작업 025). true면 폴링을 완화(재생 중 15초·일시정지 30초)
    /// 바뀌면 진행 중인 대기를 깨워 새 간격을 적용하고, false로 바뀌면 바로 1번 조회한 뒤 3초 폴링으로 돌아감
    var remoteConnected = false {
        didSet {
            guard remoteConnected != oldValue else { return }
            if !remoteConnected { waker?.pollNowRequested = true }
            waker?.wake()
        }
    }

    /// 조회 루프 1개의 대기 상태. 루프마다 새로 만들어 이전 루프와 새 루프가 대기·요청 표시를 공유하지 않게 함
    @MainActor
    private final class PollWaker {
        var sleepTask: Task<Void, Never>?   // 다음 조회까지의 대기 (연결 상태가 바뀌면 깨움)
        /// 대기를 끝내고 바로 조회. 조회를 시작할 때만 지우므로, 조회 요청 중에 들어온 요청도 다음 대기에서 반영됨
        var pollNowRequested = false
        func wake() { sleepTask?.cancel() }
    }
    private var waker: PollWaker?                // 지금 도는 루프의 대기 상태
    private var logPrefix = ""                   // SDK로 감지한 변화의 로그 앞에 붙임 ("⚡")

    /// 조회할 때마다 호출 (trackChanged: 곡이 바뀌었는지)
    var onUpdate: (@MainActor (NowPlaying?, _ trackChanged: Bool) -> Void)?
    var onLog: (@MainActor (String) -> Void)?
    /// 호출 한도로 막혔을 때 (재개 시각, 429 응답 본문). 본문은 새로 막혔을 때만 있고, 이미 막혀 있던 상태면 nil
    var onBlocked: (@MainActor (Date, String?) -> Void)?

    private let api: SpotifyAPI
    private var task: Task<Void, Never>?

    /// 마지막으로 재생이 확인된 기기. 카드 ▶︎ 버튼이 같은 기기로 재생을 요청할 때 쓰고, 앱을 껐다 켜도 남겨 둠
    /// 일시정지 중 "재생 중인 기기 없음(204)"이 와도 마지막 곡을 유지하는 기간(초). 컨트롤러가 위치 추적을 끄는 시점에 맞춰 정함
    var pausedHoldLimit: TimeInterval = 190
    private var pausedSince: TimeInterval?   // 일시정지가 시작된 시각 (기기 가동 시간 기준)
    private var holdLogged = false           // "마지막 곡을 일시정지로 유지" 로그를 한 번만 남기기 위한 표시

    private(set) var lastDevice: SpotifyDevice?
    private static let lastDeviceKey = "spotify.lastDevice"

    init(api: SpotifyAPI) {
        self.api = api
        if let data = UserDefaults.standard.data(forKey: Self.lastDeviceKey) {
            lastDevice = try? JSONDecoder().decode(SpotifyDevice.self, from: data)
        }
    }

    /// 재생 중인 기기를 기억 (기기가 바뀔 때만 저장·로그)
    private func rememberDevice(_ device: SpotifyDevice) {
        guard device.id != nil else { return }
        if lastDevice?.id != device.id {
            onLog?("🔌 재생 기기 기억: \(device.name) (\(device.type))")
        }
        guard lastDevice != device else { return }
        lastDevice = device
        if let data = try? JSONEncoder().encode(device) {
            UserDefaults.standard.set(data, forKey: Self.lastDeviceKey)
        }
    }

    var isRunning: Bool { task != nil }

    func start() {
        guard task == nil else { return }
        status = "조회 시작"
        let waker = PollWaker()
        self.waker = waker
        task = Task { [weak self] in await self?.loop(waker: waker) }
    }

    func stop() {
        task?.cancel()   // 루프의 대기도 함께 취소됨 (withTaskCancellationHandler)
        task = nil
        waker?.wake()
        waker = nil
        status = "정지"
    }

    private var uptime: TimeInterval { ProcessInfo.processInfo.systemUptime }

    /// 다음 폴링을 기다리지 않고 지금 바로 한 번 조회 (카드 버튼으로 앱을 깨운 직후 등)
    func refreshNow() async {
        do {
            let t0 = uptime
            let result = try await api.currentlyPlaying()
            let t1 = uptime
            pollCount += 1
            handlePolled(result, stamp: (t0 + t1) / 2)
        } catch SpotifyAPIError.blocked(let until, let body) {
            status = "한도 차단"
            onBlocked?(until, body)
        } catch {
            if (error as? URLError)?.code == .cancelled { return }
            onLog?("⚠️ 즉시 조회 오류: \(error.localizedDescription)")
        }
    }

    /// 다음 조회까지 기다릴 시간 = PollTiming.interval (작업 025)
    /// SDK 미연결: 재생 중 `interval`(기본 3초, 개발자 메뉴 값) / 일시정지 15초 / 곡 없음 10초 — 지금과 같음
    /// SDK 연결 중: 재생 중 15초 / 일시정지 30초 / 곡 없음 10초
    private func nextInterval() -> TimeInterval {
        let state: PollTiming.State
        if let current { state = current.isPlaying ? .playing : .paused } else { state = .none }
        if state == .playing, !remoteConnected { return interval }
        return PollTiming.interval(connected: remoteConnected, state: state)
    }

    // MARK: - SDK 이벤트 (작업 025)

    /// SDK 이벤트 뒤 이 시간(초) 동안은 Web API가 다른 곡·재생 상태를 줘도 SDK 값을 믿음
    /// (곡이 바뀐 직후엔 Web API가 아직 앞 곡을 주는 일이 있어서, 카드가 앞 곡으로 되돌아가지 않게)
    private let remoteTrust: TimeInterval = 10
    private var lastRemoteAt: TimeInterval?
    private var staleLogged = false
    /// SDK가 nil(광고·에피소드)을 줄 때 Web API 확인의 최소 간격(초). 팟캐스트·광고 중 이벤트마다 호출하지 않게
    private let remoteNilCheckGap: TimeInterval = 10
    private var lastRemoteNilCheck: TimeInterval?

    /// SDK가 알려 준 플레이어 상태를 반영. 기존 handle 경로(곡 변경·일시정지·seek 감지·로그·onUpdate)를 그대로 탐
    /// nil(광고·에피소드·해석 실패)이면 Web API로 한 번 확인 — 지금 곡이 있을 때(곡 → 곡 아님 전환)만, 최소 10초 간격
    /// 이미 곡이 없는 상태면 정규 폴링에 맡김
    func applyRemote(_ snap: RemoteSnapshot?) {
        guard isRunning else { return }
        guard let snap else {
            let now = uptime
            guard current != nil else { return }
            if let last = lastRemoteNilCheck, now - last < remoteNilCheckGap { return }
            lastRemoteNilCheck = now
            Task { await refreshNow() }
            return
        }
        let result = CurrentlyPlaying(
            type: "track", isPlaying: snap.isPlaying, progress: snap.position,
            track: CurrentlyPlaying.Track(id: snap.trackID, title: snap.title, artist: snap.artist,
                                          album: snap.album, duration: snap.duration),
            device: nil
        )
        lastRemoteAt = uptime
        staleLogged = false
        logPrefix = "⚡"
        handle(result, stamp: uptime)
        logPrefix = ""
        // 곡 변경 직후 Web API 확인은 하지 않음 (⑤ 리드 판정: 대부분 앞 곡을 줘서 버려짐). 기기 기억은 정규 폴링이 함
    }

    /// Web API 조회 결과 반영. SDK 연결 중이고 최근 SDK 이벤트와 곡·재생 상태가 다르면 Web API가 늦은 것으로 보고 무시
    private func handlePolled(_ result: CurrentlyPlaying?, stamp: TimeInterval) {
        if remoteConnected, let at = lastRemoteAt, uptime - at < remoteTrust, let current {
            let sameTrack = result?.type == "track" && result?.track?.id == current.trackID
            if !sameTrack || result?.isPlaying != current.isPlaying {
                if let result, result.isPlaying, let device = result.device { rememberDevice(device) }
                if !staleLogged {
                    staleLogged = true
                    onLog?("ℹ️ Web API가 아직 SDK와 다름 — SDK 값 유지")
                }
                onUpdate?(current, false)
                return
            }
        }
        handle(result, stamp: stamp)
    }

    private func loop(waker: PollWaker) async {
        while !Task.isCancelled {
            var wait = interval
            var polled = false   // 이번 회차 조회가 성공했는지 (곡 끝 대기는 성공한 회차에만 적용)
            // "바로 조회" 요청은 이 조회로 처리됨. 조회 요청 중에 새로 들어온 요청은 남아서 아래 대기를 건너뜀
            waker.pollNowRequested = false
            do {
                let t0 = uptime
                let result = try await api.currentlyPlaying()
                let t1 = uptime
                pollCount += 1
                handlePolled(result, stamp: (t0 + t1) / 2)   // 요청~응답 중간 시점을 기준으로
                polled = true
            } catch is CancellationError {
                break
            } catch SpotifyAPIError.blocked(let until, let body) {
                // 60초를 넘게 막힘 → 그 시각까지 조회를 완전히 멈춤. 재개는 앱 열기·▶︎·단축어 때 start()로
                status = "한도 차단"
                onBlocked?(until, body)
                task = nil
                if self.waker === waker { self.waker = nil }
                return
            } catch SpotifyAPIError.rateLimited(let after, let body) {
                // 60초 이하면 그만큼만 기다렸다 재개
                status = "호출 한도 초과"
                onLog?("⚠️ 호출 한도 초과 — \(Int(after))초 대기 \(body.isEmpty ? "" : "· \(body)")")
                wait = max(after, interval)
            } catch {
                if (error as? URLError)?.code == .cancelled { break }
                status = "오류"
                onLog?("❌ 조회 오류: \(error.localizedDescription)")
                wait = interval * 3
            }

            // 곡이 곧 끝나면 그 직후에 바로 다시 조회하고, 끝났는데 Spotify가 아직 같은 곡을 주면 잠깐 1초 간격으로 다시 봄 (작업 021)
            // 남은 시간은 곡 길이로 자르지 않은 값 (끝났으면 음수). 조회가 실패한 회차(429 대기·오류 백오프)는 줄이지 않음
            // 성공한 회차는 기다리는 동안 SDK 연결 상태가 바뀌면 깨어나 새 간격으로 다시 계산 (작업 025)
            // 대기는 waker.wake()로 깨울 수 있게 별도 Task로 두고, 루프 Task가 취소되면 함께 취소 (withTaskCancellationHandler)
            let sleepStart = uptime
            while !Task.isCancelled {
                let target = polled
                    ? PollTiming.wait(base: nextInterval(), remaining: current?.remaining(at: sleepStart))
                    : wait
                let left = sleepStart + target - uptime
                if left <= 0 || (polled && waker.pollNowRequested) { break }
                let sleeper = Task<Void, Never> { try? await Task.sleep(nanoseconds: UInt64(left * 1_000_000_000)) }
                waker.sleepTask = sleeper
                await withTaskCancellationHandler {
                    await sleeper.value
                } onCancel: {
                    sleeper.cancel()
                }
                if waker.sleepTask == sleeper { waker.sleepTask = nil }
            }
        }
    }

    private func handle(_ result: CurrentlyPlaying?, stamp: TimeInterval) {
        // 재생 중일 때 알려 주는 기기를 기억 (404 NO_ACTIVE_DEVICE 대비)
        if let result, result.isPlaying, let device = result.device { rememberDevice(device) }

        // 일시정지 중이던 곡이 있는데 204(재생 중인 기기 없음)를 받으면, 곡을 지우지 않고 마지막 곡을 일시정지로 유지 (작업 007)
        // 일시정지 후 Spotify가 잠깐 뒤에 기기 목록에서 빠지기 때문. 유지 기간은 pausedHoldLimit(= 위치 추적을 끄는 시점)까지
        if result == nil, let held = current, !held.isPlaying, let since = pausedSince, uptime - since < pausedHoldLimit {
            if !holdLogged {
                holdLogged = true
                onLog?("ℹ️ 재생 기기 없음 — 마지막 곡을 일시정지로 유지")   // 처음 한 번만
            }
            onUpdate?(held, false)
            return
        }
        if result != nil { holdLogged = false }

        guard let result, result.type == "track", let track = result.track else {
            let newStatus: String
            switch result?.type {
            case nil: newStatus = "재생 중인 곡 없음"
            case "ad": newStatus = "광고 재생 중"
            case "episode": newStatus = "팟캐스트 재생 중 (가사 없음)"
            default: newStatus = "곡 정보 없음"
            }
            let changed = current != nil
            if newStatus != status { onLog?("ℹ️ \(newStatus)") }
            current = nil
            status = newStatus
            onUpdate?(nil, changed)
            return
        }

        let new = NowPlaying(
            trackID: track.id, title: track.title, artist: track.artist, album: track.album,
            duration: track.duration, isPlaying: result.isPlaying,
            progress: result.progress, stamp: stamp
        )
        let old = current
        let trackChanged = old?.key != new.key

        // SDK로 감지한 변화는 로그 앞에 ⚡ (작업 025)
        if trackChanged {
            onLog?("\(logPrefix)🎵 곡: \(new.artist) - \(new.title) (\(Self.time(new.duration)))")
        } else if let old {
            if old.isPlaying != new.isPlaying {
                onLog?(logPrefix + (new.isPlaying ? "▶️ 재생 (\(Self.time(new.progress)))" : "⏸ 일시정지 (\(Self.time(new.progress)))"))
            } else if new.isPlaying {
                // 예상 위치와 실제 위치가 2초 넘게 다르면 → 사용자가 위치를 옮긴 것
                let drift = new.progress - old.position(at: stamp)
                if abs(drift) > 2 {
                    onLog?("\(logPrefix)⏩ 위치 이동 감지: \(Self.time(new.progress)) (\(drift > 0 ? "+" : "")\(Int(drift))초)")
                }
            }
        }

        // 일시정지가 시작된 시각 기억 (재생 중이면 지움). 같은 곡을 계속 일시정지 중이면 처음 시각을 유지
        if new.isPlaying {
            pausedSince = nil
        } else if old?.isPlaying != false || trackChanged {
            pausedSince = stamp
        }

        current = new
        status = new.isPlaying ? "재생 중" : "일시정지"
        onUpdate?(new, trackChanged)
    }

    static func time(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
