// 앱 타깃 — 순수 로직 (작업 032: 로그인 권한 판단, `swift test` 대상)
import Foundation

/// 로그인(Spotify 앱 승인) 때 요청한 권한(scope)으로 지금 필요한 권한이 모두 있는지 판단 (작업 032, 옛 웹 로그인 코드에서 옮김)
nonisolated enum LoginScopes {
    /// 로그인 때 요청한 scope(공백 구분, 기록 없으면 nil)에 required가 모두 들어 있는지 (작업 032, 옛 웹 로그인 코드에서 옮김)
    /// 순서·남는 권한·공백 개수는 따지지 않음. 권한이 줄어든 경우엔 다시 로그인하지 않아도 됨 (작업 010)
    static func isSatisfied(granted: String?, required: [String]) -> Bool {
        guard let granted else { return false }
        let grantedSet = Set(granted.split(separator: " ").map(String.init))
        return Set(required).isSubset(of: grantedSet)
    }
}
