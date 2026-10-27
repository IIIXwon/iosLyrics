// 앱 타깃 — 작업 006: 단축어 동작 "가사 추적 시작"
//
// 단축어 앱 → 자동화 → 앱 → Spotify "열 때" → 즉시 실행 → 이 동작으로 연결하면,
// Spotify를 열 때 앱을 화면에 띄우지 않고 잠금화면 카드와 위치 추적을 시작해요. (실험)
import AppIntents

/// `LiveActivityIntent`로 만들어야 iOS가 백그라운드(앱이 화면에 없는 상태)에서도 Live Activity 시작을 허락해 줘요.
/// 그냥 `AppIntent`로 두면 `Activity.request`가 "Target is not foreground" 오류로 거절돼요. (첫 테스트에서 확인)
struct StartLyricsTrackingIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "가사 추적 시작"
    static let description = IntentDescription("잠금화면 카드와 위치 추적을 시작해서 Spotify 가사를 따라가요. 앱 화면은 열지 않아요.")

    /// 앱을 화면에 띄우지 않고 백그라운드에서 실행
    static let supportedModes: IntentModes = .background

    @MainActor
    func perform() async throws -> some IntentResult {
        await ExperimentController.shared.startFromShortcut()
        return .result()
    }
}

/// 단축어 앱·Siri에 "가사 추적 시작"을 노출
struct LiveLyricsShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartLyricsTrackingIntent(),
            phrases: ["\(.applicationName) 가사 추적 시작"],
            shortTitle: "가사 추적 시작",
            systemImageName: "music.note"
        )
    }
}
