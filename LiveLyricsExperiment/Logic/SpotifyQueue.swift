// 앱 타깃 — 순수 로직 (작업 024: Spotify/SpotifyAPI.swift에서 옮김, `swift test` 대상)
import Foundation

/// 대기열의 다음 곡 (작업 021: 다음 곡 가사 미리 받기용)
nonisolated struct QueuedTrack: Equatable {
    var id: String
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval   // 초
    /// `NowPlaying.key`와 같은 규칙 (id가 비면 "아티스트|제목")
    var key: String { id.isEmpty ? "\(artist)|\(title)" : id }
}

/// GET /me/player/queue 응답 해석 (작업 021)
nonisolated enum SpotifyQueue {
    /// GET /me/player/queue 본문에서 다음 곡(queue 첫 항목). track이 아니거나 해석 실패면 nil
    static func next(from data: Data) -> QueuedTrack? {
        struct Response: Decodable {
            struct Item: Decodable {
                struct Artist: Decodable { let name: String }
                struct Album: Decodable { let name: String }
                let type: String?
                let id: String?
                let name: String?
                let durationMs: Int?
                let artists: [Artist]?
                let album: Album?
            }
            let queue: [Item]?
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let response = try? decoder.decode(Response.self, from: data),
              let item = response.queue?.first,
              item.type == "track",
              let name = item.name else { return nil }
        return QueuedTrack(
            id: item.id ?? "",
            title: name,
            artist: (item.artists ?? []).map(\.name).joined(separator: ", "),
            album: item.album?.name ?? "",
            duration: TimeInterval(item.durationMs ?? 0) / 1000
        )
    }
}
