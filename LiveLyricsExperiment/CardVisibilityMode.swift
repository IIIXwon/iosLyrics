// 앱 타깃 — 카드 표시 실험 방식 (작업 019)
// 홈 화면에서 위에서 쓸어내렸을 때(알림 센터) 카드가 바로 보이게 하려는 실험.
// 개발자 메뉴에서 고르고, 다음 [시작]부터 적용됨. 저장은 ExperimentController가 UserDefaults "cardVisibilityMode"로 함
import Foundation

/// 카드가 알림 센터에 바로 보이게 하는 실험 방식 (작업 019, 개발자 메뉴에서 선택)
nonisolated enum CardVisibilityMode: String, CaseIterable, Identifiable {
    case normal, priority, alert, both

    var id: String { rawValue }

    /// 저장된 값(rawValue)으로 만들기. 없거나 모르는 값이면 .normal
    init(stored: String?) {
        self = stored.flatMap(CardVisibilityMode.init(rawValue:)) ?? .normal
    }

    /// 개발자 메뉴 표시 이름
    var label: String {
        switch self {
        case .normal: "기본"
        case .priority: "우선순위"
        case .alert: "시작 알림"
        case .both: "둘 다"
        }
    }

    /// ActivityContent에 넘길 relevanceScore (기본 0, 우선순위 100)
    var relevanceScore: Double {
        switch self {
        case .priority, .both: 100
        case .normal, .alert: 0
        }
    }

    /// 추적 시작 후 첫 가사 갱신에 알림을 붙일지
    var alertsOnFirstLyrics: Bool {
        switch self {
        case .alert, .both: true
        case .normal, .priority: false
        }
    }
}
