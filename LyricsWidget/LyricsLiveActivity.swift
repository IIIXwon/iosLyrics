// 위젯 확장 타깃 — 잠금화면 카드 / 다이내믹 아일랜드 모양
// 카드는 가사(이전·현재·다음 줄)만 보여 주고, 다이내믹 아일랜드는 비워 둠
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
            // 다이내믹 아일랜드는 Spotify 표시가 우선이라 우리 화면은 전부 비워 둠 (자리를 차지하지 않기 위해)
            DynamicIsland {
                // 빈 expanded는 컴파일되지 않아 빈 영역 하나만 둠
                DynamicIslandExpandedRegion(.center) { EmptyView() }
            } compactLeading: {
                EmptyView()
            } compactTrailing: {
                EmptyView()
            } minimal: {
                EmptyView()
            }
            .widgetURL(URL(string: "livelyrics://open-spotify"))
        }
    }
}

struct LockScreenLyricsView: View {
    let state: LyricsActivityAttributes.ContentState

    var body: some View {
        VStack(spacing: 4) {
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
        // 전주·간주 끝 3초: 왼쪽 위에 3·2·1 (작업 020). overlay라 가사 줄 위치·크기는 그대로
        .overlay(alignment: .topLeading) {
            if state.countdown > 0 {
                Text("\(state.countdown)")
                    .font(.caption.bold())
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.top, 10)
                    .padding(.leading, 14)
            }
        }
    }
}
