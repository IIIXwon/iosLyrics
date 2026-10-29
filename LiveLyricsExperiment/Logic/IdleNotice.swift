// 앱 타깃 — 위치 추적을 끄기 직전 카드에 남겨 두는 안내 문구 (작업 026)
import Foundation

/// 위치 추적을 끄기 직전 카드에 남겨 두는 안내 (작업 026: 카드에서 재생 제어 없음 → Spotify에서 직접 재생 안내)
nonisolated enum IdleNotice {
    static let current = "⏸ 일시정지"
    static let next = "카드를 눌러 Spotify에서 재생해 주세요"
}
