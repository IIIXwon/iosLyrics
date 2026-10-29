// 앱 타깃 — Spotify Web API: 현재 재생 중인 곡 조회
import Foundation

/// 현재 재생 정보 (필요한 것만)
struct CurrentlyPlaying {
    struct Track {
        let id: String
        let title: String
        let artist: String
        let album: String
        let duration: TimeInterval   // 초
    }
    let type: String          // "track", "episode", "ad", "unknown"
    let isPlaying: Bool
    let progress: TimeInterval   // 초
    let track: Track?
}

// QueuedTrack·SpotifyQueue(대기열 응답 해석)는 LiveLyricsExperiment/Logic/SpotifyQueue.swift로 옮김 (작업 024)

enum SpotifyAPIError: LocalizedError {
    case rateLimited(retryAfter: TimeInterval, body: String)   // 60초 이하로 기다리면 되는 429
    case blocked(until: Date, body: String?)                    // 60초를 넘게 막힘(한도 차단). 그 시각까지 호출하지 않음 (작업 008)
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .rateLimited(let after, _): return "호출 한도 초과 (\(Int(after))초 뒤 재시도)"
        case .blocked(let until, _): return "한도 차단 중 — \(SpotifyBlock.untilText(until)) 이후 재개"
        case .http(let code, let body):
            if code == 403 { return "접근 거부 (HTTP 403) — Premium 구독, 대시보드 User Management 등록을 확인하세요: \(body)" }
            return "HTTP \(code): \(body)"
        }
    }
}

@MainActor
final class SpotifyAPI {
    private let auth: SpotifyAuth

    init(auth: SpotifyAuth) {
        self.auth = auth
    }

    /// 현재 재생 중인 곡. 아무것도 재생 중이 아니면 nil
    /// `/me/player`(재생 상태) 응답에서 곡·재생 여부·위치만 씀 (기기 정보는 작업 026에서 재생 요청과 함께 삭제)
    func currentlyPlaying() async throws -> CurrentlyPlaying? {
        guard let data = try await get("https://api.spotify.com/v1/me/player") else {
            return nil   // 204: 재생 중인 기기 없음
        }

        struct Response: Decodable {
            struct Item: Decodable {
                struct Artist: Decodable { let name: String }
                struct Album: Decodable { let name: String }
                let id: String?
                let name: String
                let durationMs: Int
                let artists: [Artist]?
                let album: Album?
            }
            let isPlaying: Bool
            let progressMs: Int?
            let currentlyPlayingType: String?
            let item: Item?
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let r = try decoder.decode(Response.self, from: data)

        let track = r.item.map { item in
            CurrentlyPlaying.Track(
                id: item.id ?? "",
                title: item.name,
                artist: (item.artists ?? []).map(\.name).joined(separator: ", "),
                album: item.album?.name ?? "",
                duration: TimeInterval(item.durationMs) / 1000
            )
        }
        return CurrentlyPlaying(
            type: r.currentlyPlayingType ?? "unknown",
            isPlaying: r.isPlaying,
            progress: TimeInterval(r.progressMs ?? 0) / 1000,
            track: track
        )
    }

    /// 대기열의 다음 곡 (GET /v1/me/player/queue, 작업 021). 대기열이 비었거나 다음이 곡이 아니면(에피소드 등) nil
    /// scope `user-read-playback-state`로 가능 (재로그인 불필요)
    func nextInQueue() async throws -> QueuedTrack? {
        guard let data = try await get("https://api.spotify.com/v1/me/player/queue", kind: .queue) else { return nil }
        return SpotifyQueue.next(from: data)
    }

    /// GET 요청. 200 → 데이터, 204 → nil. 401이면 토큰 갱신 후 한 번 재시도
    private func get(_ urlString: String, kind: APIUsage.Kind = .state, retry: Bool = true) async throws -> Data? {
        try ensureNotBlocked()
        let token = try await auth.validAccessToken()
        var request = URLRequest(url: URL(string: urlString)!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        APIUsage.record(kind)
        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? 0

        switch status {
        case 200:
            return data
        case 204:
            return nil
        case 401 where retry:
            _ = try await auth.refresh()
            return try await get(urlString, kind: kind, retry: false)
        case 429:
            throw rateLimitError(http, data)
        default:
            throw SpotifyAPIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
    }

    /// 차단 중이면(재개 시각 전) 네트워크 요청을 보내지 않고 바로 오류
    private func ensureNotBlocked() throws {
        if let until = SpotifyBlock.until { throw SpotifyAPIError.blocked(until: until, body: nil) }
    }

    /// 429 처리: Retry-After가 60초 이하면 그만큼 기다리면 되는 오류, 60초를 넘으면 재개 시각을 저장하고 "한도 차단"
    private func rateLimitError(_ http: HTTPURLResponse?, _ data: Data) -> SpotifyAPIError {
        let after = TimeInterval(http?.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 5
        let body = String(data: data, encoding: .utf8) ?? ""
        guard after > 60 else { return .rateLimited(retryAfter: after, body: body) }
        let until = Date().addingTimeInterval(after)
        SpotifyBlock.set(until)
        return .blocked(until: until, body: body)
    }
}
