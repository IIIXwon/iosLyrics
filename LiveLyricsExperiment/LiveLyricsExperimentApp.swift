// 앱 타깃 — 앱 진입점
// Xcode가 자동으로 만든 LiveLyricsExperimentApp.swift를 이 내용으로 바꾸세요.
import SwiftUI

@main
struct LiveLyricsExperimentApp: App {
    @StateObject private var controller = ExperimentController.shared

    init() {
        // 카드의 ▶︎ 버튼이 앱을 깨우면 iOS는 화면 없이 앱을 시작할 수 있어요.
        // 그래서 화면(body)이 아니라 앱이 시작되는 이 시점에 동작을 연결해 둬요.
        IntentBridge.onResume = { await ExperimentController.shared.resumeFromCard() }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(controller)
        }
    }
}
