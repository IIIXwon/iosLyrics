// 위젯 확장 타깃의 진입점
// Xcode가 자동으로 만든 ...Bundle.swift 파일을 이 내용으로 바꾸세요.
import SwiftUI
import WidgetKit

@main
struct LyricsWidgetBundle: WidgetBundle {
    var body: some Widget {
        LyricsLiveActivity()
    }
}
