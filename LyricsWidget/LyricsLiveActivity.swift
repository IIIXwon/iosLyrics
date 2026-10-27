// 위젯 확장 타깃 — 잠금화면 카드 / 다이내믹 아일랜드 모양
// 개선 1: 재생 시간과 진행 막대가 갱신 없이도 스스로 흘러감
import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

struct LyricsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LyricsActivityAttributes.self) { context in
            LockScreenLyricsView(state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.35))
                .activitySystemActionForegroundColor(.white)
                // 카드를 누르면 앱이 이 주소를 받아 Spotify 앱을 열어요 (작업 009). ▶︎ 버튼 영역은 버튼(인텐트)이 우선
                .widgetURL(URL(string: "livelyrics://open-spotify"))

        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "music.note").foregroundStyle(.green)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.trackInfo.isEmpty ? context.state.previous : context.state.trackInfo)
                        .font(.caption).lineLimit(1)
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 4) {
                        Text(context.state.current)
                            .font(.headline).lineLimit(1)
                        PlaybackTimeRow(state: context.state)
                    }
                }
            } compactLeading: {
                Image(systemName: "music.note").foregroundStyle(.green)
            } compactTrailing: {
                Text(context.state.current)
                    .font(.caption2).lineLimit(1)
                    .frame(maxWidth: 70)
            } minimal: {
                Image(systemName: "music.note").foregroundStyle(.green)
            }
        }
    }
}

struct LockScreenLyricsView: View {
    let state: LyricsActivityAttributes.ContentState

    var body: some View {
        VStack(spacing: 4) {
            if !state.trackInfo.isEmpty {
                Text(state.trackInfo)
                    .font(.caption2).foregroundStyle(.white.opacity(0.4))
            }
            if !state.previous.isEmpty {
                Text(state.previous)
                    .font(.caption).foregroundStyle(.white.opacity(0.5))
            }
            // 현재 줄만 2줄까지 (바깥 VStack의 lineLimit(1)보다 안쪽 설정이 우선). 긴 줄이 잘리지 않게
            Text(state.current)
                .font(.headline).foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            if !state.next.isEmpty {
                Text(state.next)
                    .font(.caption).foregroundStyle(.white.opacity(0.45))
            }
            PlaybackTimeRow(state: state)
                .padding(.top, 4)
            // 일시정지 상태일 때만: 누르면 앱을 깨워 재생·위치 추적·가사를 다시 연결
            if !state.isPlaying {
                Button(intent: ResumeLyricsIntent()) {
                    Text("▶︎ 가사 다시 켜기")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(.white.opacity(0.18), in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .lineLimit(1)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
    }
}

/// 재생 시간 + 진행 막대
/// 재생 중이면 iOS가 매 초 알아서 그려 줘서, 앱이 카드를 갱신하지 않아도 움직여요.
struct PlaybackTimeRow: View {
    let state: LyricsActivityAttributes.ContentState

    var body: some View {
        if let start = state.trackStart, let end = state.trackEnd, end > start {
            HStack(spacing: 8) {
                if state.isPlaying {
                    // 스스로 흐르는 시계 (0:00 → 곡 길이)
                    Text(timerInterval: start...end, countsDown: false)
                        .monospacedDigit()
                        .frame(width: 40, alignment: .leading)
                    // 스스로 차오르는 진행 막대
                    ProgressView(timerInterval: start...end, countsDown: false) {
                        EmptyView()
                    } currentValueLabel: {
                        EmptyView()
                    }
                    .tint(.white)
                } else {
                    Text(Self.time(state.pausedPosition))
                        .monospacedDigit()
                        .frame(width: 40, alignment: .leading)
                    ProgressView(value: state.duration > 0 ? min(1, state.pausedPosition / state.duration) : 0)
                        .tint(.white.opacity(0.5))
                    Image(systemName: "pause.fill")
                }
                Text(Self.time(state.duration))
                    .monospacedDigit()
                    .frame(width: 40, alignment: .trailing)
            }
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.6))
        }
    }

    static func time(_ seconds: Double) -> String {
        let s = max(0, Int(seconds))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
