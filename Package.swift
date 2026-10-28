// swift-tools-version: 6.2
// 작업 024: 순수 로직 단위 테스트를 시뮬레이터 없이 Mac에서 실행 (`swift test`)
// 앱은 계속 LiveLyricsExperiment.xcodeproj로 연다. 이 패키지는 테스트 전용이다.
import PackageDescription

let package = Package(
    name: "LiveLyricsLogic",
    platforms: [.macOS(.v15)],
    targets: [
        // 앱 타깃과 같은 모듈 이름 → 테스트의 `@testable import LiveLyricsExperiment`를 그대로 쓴다
        .target(
            name: "LiveLyricsExperiment",
            path: "LiveLyricsExperiment/Logic",
            swiftSettings: [.defaultIsolation(MainActor.self), .swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "LiveLyricsTests",
            dependencies: ["LiveLyricsExperiment"],
            path: "LiveLyricsTests",
            swiftSettings: [.defaultIsolation(MainActor.self), .swiftLanguageMode(.v5)]
        ),
    ]
)
