// 앱 타깃 — 앱 진입점
// Xcode가 자동으로 만든 LiveLyricsExperimentApp.swift를 이 내용으로 바꾸세요.
import SwiftUI

@main
struct LiveLyricsExperimentApp: App {
    @StateObject private var controller = ExperimentController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(controller)
        }
    }
}
