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
    let device: SpotifyDevice?   // 지금 재생 중인 기기 (▶︎ 버튼이 같은 기기로 재생을 요청할 때 사용)
}

/// Spotify 연결 기기 (이 아이폰의 Spotify 앱도 하나의 "기기"로 보임)
nonisolated struct SpotifyDevice: Codable, Equatable {
    let id: String?          // 일부 기기는 id가 없을 수 있음
    let name: String
    let type: String         // "Smartphone", "Computer", "Speaker" …
    let isActive: Bool
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
    /// `/me/player`는 `/me/player/currently-playing`과 같은 정보에 재생 기기(device)까지 줘서, 호출 횟수는 그대로 두고 기기 ID를 기억할 수 있음
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
            let device: SpotifyDevice?
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
            track: track,
            device: r.device
        )
    }

    /// 재생 재개 (PUT /v1/me/player/play, 본문 없음). 성공하면 HTTP 상태 코드(보통 204)를 돌려줌
    /// deviceID를 주면 그 기기로 재생을 요청 (`?device_id=`)
    /// 실패: 404 = 재생할 기기 없음(NO_ACTIVE_DEVICE), 403 = 권한(scope) 부족 또는 이미 재생 중 등 제한
    @discardableResult
    func play(deviceID: String? = nil) async throws -> Int {
        var urlString = "https://api.spotify.com/v1/me/player/play"
        if let deviceID,
           let encoded = deviceID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            urlString += "?device_id=\(encoded)"
        }
        return try await put(urlString)
    }

    /// 연결된 기기 목록 (GET /v1/me/player/devices). 이름·종류·활성 여부를 로그에 남기는 용도
    func devices() async throws -> [SpotifyDevice] {
        guard let data = try await get("https://api.spotify.com/v1/me/player/devices", kind: .devices) else { return [] }
        struct Response: Decodable { let devices: [SpotifyDevice] }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Response.self, from: data).devices
    }

    /// 대기열의 다음 곡 (GET /v1/me/player/queue, 작업 021). 대기열이 비었거나 다음이 곡이 아니면(에피소드 등) nil
    /// scope `user-read-playback-state`로 가능 (재로그인 불필요)
    func nextInQueue() async throws -> QueuedTrack? {
        guard let data = try await get("https://api.spotify.com/v1/me/player/queue", kind: .queue) else { return nil }
        return SpotifyQueue.next(from: data)
    }

    /// 재생을 다른 기기로 옮기고 재생 (PUT /v1/me/player, 재생 이전). 성공하면 HTTP 상태 코드
    @discardableResult
    func transferPlayback(to deviceID: String, play: Bool) async throws -> Int {
        let body = try JSONSerialization.data(withJSONObject: ["device_ids": [deviceID], "play": play])
        return try await put("https://api.spotify.com/v1/me/player", body: body)
    }

    /// PUT 요청. 200·202·204 → 상태 코드. 401이면 토큰 갱신 후 한 번 재시도
    private func put(_ urlString: String, body: Data? = nil, retry: Bool = true) async throws -> Int {
        try ensureNotBlocked()
        let token = try await auth.validAccessToken()
        var request = URLRequest(url: URL(string: urlString)!)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        } else {
            request.setValue("0", forHTTPHeaderField: "Content-Length")   // 본문 없는 PUT은 길이 0을 요구함
        }
        request.timeoutInterval = 10

        APIUsage.record(.play)
        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? 0

        switch status {
        case 200, 202, 204:
            return status
        case 401 where retry:
            _ = try await auth.refresh()
            return try await put(urlString, body: body, retry: false)
        case 429:
            throw rateLimitError(http, data)
        default:
            throw SpotifyAPIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
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
