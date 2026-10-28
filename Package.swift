// swift-tools-version: 6.2
// 작업 024: 순수 로직 단위 테스트를 시뮬레이터 없이 Mac에서 실행 (`swift test`)
// 앱은 계속 LiveLyricsExperiment.xcodeproj로 연다. 이 패키지는 테스트 전용이다.
import PackageDescription

// xcodeproj 빌드 설정과 맞춤 (SWIFT_APPROACHABLE_CONCURRENCY, SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY, SWIFT_VERSION 5.0)
let common: [SwiftSetting] = [
    .swiftLanguageMode(.v5),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("MemberImportVisibility"),
]

let package = Package(
    name: "LiveLyricsLogic",
    platforms: [.macOS(.v26)],  // 앱 iOS 26과 같은 세대
    targets: [
        // 앱 타깃과 같은 모듈 이름 → 테스트의 `@testable import LiveLyricsExperiment`를 그대로 쓴다
        .target(
            name: "LiveLyricsExperiment",
            path: "LiveLyricsExperiment/Logic",
            // 앱 타깃처럼 SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor
            swiftSettings: common + [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "LiveLyricsTests",
            dependencies: ["LiveLyricsExperiment"],
            path: "LiveLyricsTests",
            // Xcode 테스트 타깃엔 기본 MainActor 격리가 없음 → 여기도 없음 (리뷰 반영)
            swiftSettings: common
        ),
    ]
)
