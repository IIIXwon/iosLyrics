// 순수 로직 — Spotify SDK 연결 시도·실패 로그를 "남길지" 판단하고 기록 (작업 034, ExperimentController에서 옮김)
// 연결 호출과 로그 출력은 ExperimentController에 남아 있음. ⚠️ 토큰·세션 값은 넣지 않음 (있음/없음·남은 시간만)
import Foundation

/// SDK 연결 진단 기록. 추적 세션마다 새로 시작 (`RemoteConnectLog()`로 초기화)
nonisolated struct RemoteConnectLog: Equatable {
    enum FailureLine: Equatable {
        case detail     // 상세 줄
        case repeated   // "같은 오류 반복" 짧은 줄
        case silent     // 줄 없음
    }

    private(set) var lastAttempt: TimeInterval?      // 마지막 연결 시도 시각 (기기 가동 시간 기준)
    private var lastFailure: String?                  // 마지막 실패 키(domain+code)
    private(set) var attemptCount = 0                 // 연결 시도 번호 (진단 로그용)
    private var authWarned = false                    // "승인 필요" 안내를 이번 세션에 이미 남겼는지
    private(set) var attemptAppState: String?         // 마지막 연결 시도 때의 앱 상태
    private var lastOutcome: String?                  // 직전 시도 결과: "성공" 또는 실패 키
    private var backgroundLogged = false              // 이번 세션에 백그라운드 시도 줄을 남긴 적 있는지
    private var outcomeAtBackgroundLog: String?       // 마지막으로 백그라운드 시도 줄을 남길 때의 직전 결과
    private var attemptLogged = false                 // 마지막 연결 시도 줄을 남겼는지
    var connectAfterAttempt = false                   // 승인 뒤 이전 시도가 진행 중 → 그 시도가 실패하면 새 세션으로 다시 연결 (029)

    init() {}

    /// 시도 기록. 반환값: 이 시도의 줄을 남길지
    /// 앱 화면 시도는 항상, 백그라운드 시도는 세션 첫 번째이거나 직전 결과가 바뀌었을 때만
    mutating func attemptStarted(now: TimeInterval, foreground: Bool, appState: String) -> Bool {
        lastAttempt = now
        authWarned = false
        attemptCount += 1
        attemptAppState = appState
        attemptLogged = foreground || !backgroundLogged || lastOutcome != outcomeAtBackgroundLog
        if attemptLogged, !foreground {
            backgroundLogged = true
            outcomeAtBackgroundLog = lastOutcome
        }
        return attemptLogged
    }

    /// 승인이 없어 막힘. 반환값: 안내를 남길지 (세션당 1번). 다음 백그라운드 확인은 60초 뒤
    mutating func needAuthorize(now: TimeInterval) -> Bool {
        lastAttempt = now
        guard !authWarned else { return false }
        authWarned = true
        return true
    }

    /// Spotify 앱 승인이 끝남 → 안내를 다시 남길 수 있게 함
    mutating func authorized() {
        authWarned = false
    }

    /// 연결됨
    mutating func connected() {
        connectAfterAttempt = false   // 이전 시도가 성공했으면 다시 연결할 필요 없음
        lastFailure = nil
        lastOutcome = "성공"
    }

    /// 연결 실패. 같은 실패(키)가 연속이면 상세 대신 짧은 줄, 시도 줄을 생략했으면 그것도 생략
    mutating func failed(key: String) -> FailureLine {
        lastOutcome = key
        if key == lastFailure {
            return attemptLogged ? .repeated : .silent
        }
        lastFailure = key
        return .detail
    }
}

/// SDK 연결 로그 문구
nonisolated enum RemoteLogText {
    /// SDK 승인 세션의 남은 시간 한 줄. ⚠️ 세션·토큰 값은 넣지 않음
    static func session(hasSession: Bool, remaining: TimeInterval?) -> String {
        guard hasSession, let seconds = remaining else { return "세션 없음" }
        if seconds <= 0 { return "세션 있음, 만료됨(연결 전 갱신)" }
        if seconds <= RemoteAuthPlan.renewMargin { return "세션 있음, 남은 유효 곧 만료(연결 전 갱신)" }
        return "세션 있음, 남은 유효 \(Int(seconds / 60))분"
    }

    /// 재생 상태 (nil = 곡 없음)
    static func playback(isPlaying: Bool?) -> String {
        guard let isPlaying else { return "없음" }
        return isPlaying ? "재생 중" : "일시정지"
    }

    static func disconnected(byUser: Bool, error: String?) -> String {
        if byUser {
            // 우리가 끊은 경우. 정지·강제 종료·로그아웃은 폴링도 함께 멈추므로 "3초 폴링 복귀"가 아님
            return "⚡ SDK 연결 끊음 (\(error ?? "정지"))"
        }
        return "⚡ SDK 연결 끊김 — 3초 폴링 복귀 (\(error ?? "이유 없음"))"
    }

    static func needAuthorize(hasSession: Bool) -> String {
        if hasSession {
            // 한 번 승인함 → 카드 탭 때 승인 왕복으로 자동 재승인 (작업 030)
            return "⚡ SDK 세션 만료·갱신 불가 — 잠금화면 카드를 탭하면 Spotify를 잠깐 거쳐 자동으로 다시 승인해요 (앱의 [Spotify 다시 연결]도 가능)"
        }
        return "⚡ Spotify 로그인 필요 — 앱에서 [Spotify로 로그인]을 눌러 주세요"
    }

    /// 295초 → "4분 55초", 42초 → "42초"
    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return total >= 60 ? "\(total / 60)분 \(total % 60)초" : "\(total)초"
    }
}
