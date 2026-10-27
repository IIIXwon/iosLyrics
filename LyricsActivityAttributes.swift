// ⚠️ 앱 타깃과 위젯 확장 타깃 "둘 다"에 포함 (Target Membership 두 개 체크)
import ActivityKit
import AppIntents
import Foundation

nonisolated struct LyricsActivityAttributes: ActivityAttributes {
    /// 카드 내용 (바뀔 때만 갱신)
    public struct ContentState: Codable, Hashable {
        var previous: String       // 위 작은 줄
        var current: String        // 가운데 큰 줄
        var next: String           // 아래 작은 줄

        // ── 3단계: 곡 정보 (013부터 카드에 표시하지 않음, 형식 유지용) ──
        var trackInfo: String = ""   // "제목 · 아티스트" (비어 있으면 안 보임)

        // ── 개선 1: 재생 시간 (013부터 카드에 표시하지 않음, 형식 유지용) ──
        var isPlaying: Bool = false
        /// 곡의 0초 지점에 해당하는 시각 (= 지금 - 재생 위치)
        var trackStart: Date? = nil
        /// 곡이 끝나는 시각 (= trackStart + 곡 길이)
        var trackEnd: Date? = nil
        /// 일시정지 상태일 때 멈춘 위치 (초)
        var pausedPosition: Double = 0
        /// 곡 길이 (초)
        var duration: Double = 0
    }

    var title: String
    var artist: String
}

// MARK: - 카드의 ▶︎ "가사 다시 켜기" 버튼 (작업 001)
// 이 파일은 앱·위젯 두 타깃에 모두 들어 있어서 인텐트도 같이 두었어요.
// 위젯은 버튼 모양만 만들고, 실제 실행(perform)은 iOS가 앱 프로세스를 깨워서 해요.
// 앱 전용 코드(ExperimentController 등)는 위젯 타깃에서 컴파일되지 않으므로
// IntentBridge를 거쳐 호출하고, 앱이 시작될 때(LiveLyricsExperimentApp.init) 연결해요.

nonisolated enum IntentBridge {
    /// 앱이 시작할 때 등록하는 "가사 다시 켜기" 동작
    @MainActor static var onResume: (@MainActor () async -> Void)?
}

nonisolated struct ResumeLyricsIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "가사 다시 켜기"
    static let isDiscoverable = false   // 단축어 앱에는 노출하지 않음

    func perform() async throws -> some IntentResult {
        await IntentBridge.onResume?()
        return .result()
    }
}
