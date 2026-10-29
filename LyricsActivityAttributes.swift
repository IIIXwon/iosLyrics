// ⚠️ 앱 타깃과 위젯 확장 타깃 "둘 다"에 포함 (Target Membership 두 개 체크)
import ActivityKit
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

        // ── 작업 020: 전주·간주 카운트다운 ──
        /// 3·2·1이면 카드 왼쪽 위에 표시, 0이면 숨김
        var countdown: Int = 0
    }

    var title: String
    var artist: String
}
