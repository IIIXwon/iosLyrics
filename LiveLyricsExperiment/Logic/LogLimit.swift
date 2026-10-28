// 앱 타깃 — 순수 로직 (작업 024: ExperimentController.swift에서 옮김, `swift test` 대상)
import Foundation

/// 앱 로그 보관 줄 수 (작업 019 검토 1차: 복사·붙여 넣기가 되도록 100줄)
nonisolated enum LogLimit {
    static let maxLines = 100
    /// 최신 줄이 앞(index 0)인 배열에서 maxLines를 넘는 오래된 줄을 버림
    static func trimmed(_ logs: [String]) -> [String] {
        logs.count > maxLines ? Array(logs.prefix(maxLines)) : logs
    }
}
