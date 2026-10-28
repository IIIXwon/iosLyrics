// 앱 타깃 — LRCLIB에서 가사를 검색하고, 앱 전용 폴더에 저장하고, LRC를 파싱
//
// ⚖️ 가사는 "조회"해서 이 기기 안에만 저장해요. 서버에 올리거나 재배포하지 않고 LRCLIB에 업로드하지도 않아요.
import Foundation

/// 가사 한 줄 (time: 곡 시작 후 몇 초에 나오는지)
nonisolated struct LyricLine: Equatable {
    let time: TimeInterval
    let text: String
}

/// 지금 위치에서 보여 줄 이전 / 현재 / 다음 줄
nonisolated struct LyricContext: Equatable {
    var previous: String
    var current: String
    var next: String
    /// 다음 줄이 나오는 시각(초). 마지막 줄이면 nil
    var nextTime: TimeInterval?
}

/// 찾은 가사의 종류
nonisolated enum LyricsKind: Equatable {
    case synced         // 줄마다 시간이 있는 가사 (카드에 줄 단위로 표시)
    case plain          // 시간 정보 없는 일반 가사 (저장만 하고 카드에는 "싱크 없음" 안내)
    case instrumental   // 가사 없는 연주곡 (제목 규칙 InstrumentalTitle로만 판단. LRCLIB의 연주곡 표시는 믿지 않음)
    case none           // 못 찾음
}

/// 가사 검색 결과
nonisolated struct LyricsResult {
    var kind: LyricsKind
    var lines: [LyricLine] = []   // synced 일 때만
    var lrc = ""                  // synced 원문 (저장용)
    var plain = ""                // plain 원문 (저장용)
    var stage = 0                 // 몇 번째 검색 단계에서 찾았는지 (로그용)
    var stageName = ""
    var summary = ""              // 시도한 단계까지의 결과 요약 (못 찾은 곡 기록용)
}

/// 곡별 마지막 검색 기록 (재검색 간격 판단 + "못 찾은 곡" 목록용). `search-log.json`에 저장
nonisolated struct SearchRecord: Codable, Equatable {
    var key: String        // "아티스트 - 제목" (저장 파일 이름과 같음)
    var title: String
    var artist: String
    var album: String
    var duration: Double   // 곡 길이(초)
    var result: String     // "plain" 일반 가사만 / "none" 못 찾음 / "instrumental" 연주곡(LRCLIB 표시)
    var searchedAt: Date   // 마지막 검색 시각
    var summary: String    // 시도한 단계까지의 결과 요약

    /// 마지막 검색이 maxAge초 안이면 true (재검색 간격 판단)
    func isFresh(within maxAge: TimeInterval) -> Bool {
        Date().timeIntervalSince(searchedAt) < maxAge
    }

    /// "방금 전" / "5분 전" / "3시간 전" / "2일 전"
    var agoText: String {
        let seconds = Int(Date().timeIntervalSince(searchedAt))
        if seconds < 60 { return "방금 전" }
        if seconds < 3600 { return "\(seconds / 60)분 전" }
        if seconds < 86400 { return "\(seconds / 3600)시간 전" }
        return "\(seconds / 86400)일 전"
    }
}

nonisolated enum LRCParser {
    /// "[01:23.45] 가사" 형식을 줄 목록으로. 시간 태그가 여러 개인 줄도 처리
    static func parse(_ lrc: String) -> [LyricLine] {
        var result: [LyricLine] = []
        for raw in lrc.split(whereSeparator: \.isNewline) {
            var rest = Substring(raw)
            var times: [TimeInterval] = []
            while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
                let tag = rest[rest.index(after: rest.startIndex)..<close]
                guard let t = timestamp(tag) else { break }   // [ar:가수] 같은 정보 태그는 무시
                times.append(t)
                rest = rest[rest.index(after: close)...]
            }
            let text = rest.trimmingCharacters(in: .whitespaces)
            for t in times { result.append(LyricLine(time: t, text: text)) }
        }
        return result.sorted { $0.time < $1.time }
    }

    /// "01:23.45" → 83.45
    private static func timestamp(_ tag: Substring) -> TimeInterval? {
        let parts = tag.split(separator: ":")
        guard parts.count == 2, let minutes = Double(parts[0]), let seconds = Double(parts[1]) else { return nil }
        return minutes * 60 + seconds
    }

    /// 재생 위치에 맞는 줄 찾기. 빈 줄(간주)은 ♪ 로 표시
    static func context(_ lines: [LyricLine], at position: TimeInterval) -> LyricContext {
        func show(_ i: Int) -> String {
            guard lines.indices.contains(i) else { return "" }
            return lines[i].text.isEmpty ? "♪" : lines[i].text
        }
        let index = lines.lastIndex { $0.time <= position } ?? -1
        let nextTime = lines.indices.contains(index + 1) ? lines[index + 1].time : nil
        return LyricContext(
            previous: show(index - 1),
            current: index >= 0 ? show(index) : "♪",
            next: show(index + 1),
            nextTime: nextTime
        )
    }
}

/// 전주·간주 끝 3초 동안 카드에 보일 3·2·1 (작업 020)
nonisolated enum LyricCountdown {
    /// 숫자를 보이는 시간(초) — 다음 줄 직전 3초
    static let seconds: TimeInterval = 3
    /// 전주(첫 줄 전) 최소 길이. 첫 줄이 이보다 빨리 나오면 숫자 없음
    static let introMinimum: TimeInterval = 5
    /// 간주(빈 줄 ~ 다음 줄) 최소 길이
    static let interludeMinimum: TimeInterval = 8

    /// 지금 위치에서 보일 숫자 (3·2·1). 안 보이면 0
    static func value(_ lines: [LyricLine], at position: TimeInterval) -> Int {
        guard let target = countdownTarget(lines, at: position) else { return 0 }
        let remaining = target - position
        guard remaining > 0, remaining <= seconds else { return 0 }
        return Int(remaining.rounded(.up))   // 3.0 → 3, 2.5 → 3, 0.5 → 1
    }

    /// 숫자가 다음에 바뀌는 위치(초). 다음 변화가 줄 바뀜이거나 카운트다운 구간이 아니면 nil
    static func nextChange(_ lines: [LyricLine], at position: TimeInterval) -> TimeInterval? {
        guard let target = countdownTarget(lines, at: position) else { return nil }
        let shown = value(lines, at: position)
        if shown == 0 { return target - seconds }   // 아직 숫자 전 → 3이 나타나는 시각
        if shown == 1 { return nil }                // 1 다음은 줄 바뀜 (기존 예약이 처리)
        return target - TimeInterval(shown - 1)     // 3 → 2, 2 → 1로 바뀌는 시각
    }

    /// 지금이 카운트다운 대상 구간(긴 전주·긴 간주)이면 대상 줄 시각, 아니면 nil
    /// 대상 = 지금 위치 뒤의 첫 번째 글자 있는 줄 (빈 줄이 이어져도 건너뜀, 리뷰 1차)
    private static func countdownTarget(_ lines: [LyricLine], at position: TimeInterval) -> TimeInterval? {
        guard let target = lines.first(where: { $0.time > position && !$0.text.isEmpty })?.time else {
            return nil   // 뒤에 글자 있는 줄이 없음
        }
        // 전주: 지금 위치까지 글자 있는 줄이 하나도 없음 (빈 줄로 시작하는 LRC 포함)
        let hasSungLine = lines.contains { $0.time <= position && !$0.text.isEmpty }
        if !hasSungLine {
            return target >= introMinimum ? target : nil
        }
        // 간주: 현재 줄이 빈 줄(카드에 ♪)이고 그 빈 줄부터 대상 줄까지 충분히 길 때
        guard let current = lines.last(where: { $0.time <= position }), current.text.isEmpty else { return nil }
        return target - current.time >= interludeMinimum ? target : nil
    }
}

/// 로그에 상태 코드가 보이도록 (예: HTTP 503)
nonisolated enum LyricsError: LocalizedError {
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .http(let code): return "서버 응답 오류 (HTTP \(code))"
        }
    }
}

/// 가사 조회 재시도 규칙 (작업 012)
nonisolated enum LyricsRetryPolicy {
    /// 잠시 뒤 다시 시도하면 될 수 있는 오류인지 (서버 5xx·429·네트워크)
    static func isTransient(_ error: Error) -> Bool {
        if let lyricsError = error as? LyricsError {
            switch lyricsError {
            case .http(let code): return code >= 500 || code == 429
            }
        }
        if let urlError = error as? URLError {
            return urlError.code != .cancelled
        }
        return false
    }

    /// n번째 실패 뒤 기다릴 초. nil이면 더 시도하지 않음
    static func delay(afterFailure attempt: Int) -> TimeInterval? {
        switch attempt {
        case 1: return 2
        case 2: return 5
        case 3: return 15
        case 4: return 30
        case 5: return 60
        default: return nil
        }
    }
}

// MARK: - 검색 보강용 문자열 정리

nonisolated enum TitleCleaner {
    /// 제목 꼬리 떼기: (feat. …) (with …) - Remastered - 2011 Remaster (Radio Edit) 등
    /// Live / Remix / Acoustic 은 다른 버전이라 타이밍이 달라서 떼지 않음
    static func clean(_ title: String) -> String {
        let patterns = [
            #"\s*[\(\[]\s*(feat|ft|featuring|with|prod)\b[^\)\]]*[\)\]]"#,
            #"\s*[\(\[]\s*((\d{4}\s*)?remaster(ed)?(\s*\d{4})?|radio edit|single version|album version)[^\)\]]*[\)\]]"#,
            #"\s+-\s+(feat|ft)\.?\s.*$"#,
            #"\s+-\s+((\d{4}\s*)?remaster(ed)?(\s*\d{4})?|radio edit|single version|album version|mono|stereo)\b.*$"#,
        ]
        var result = title
        for pattern in patterns {
            result = result.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }
        let trimmed = result.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? title : trimmed
    }

    /// "A, B, C" → "A" (Spotify는 아티스트 여러 명을 쉼표로 이어서 줌)
    static func firstArtist(_ artist: String) -> String {
        let first = artist.split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) }
        return (first?.isEmpty == false ? first : nil) ?? artist
    }
}

/// 제목만 봐도 연주곡인 곡은 LRCLIB을 검색하지 않고 바로 연주곡으로 처리 (작업 005)
nonisolated enum InstrumentalTitle {
    /// - 어디에 있든: `instrumental` (단어 단위)
    /// - 괄호·대괄호 안이거나 " - " 뒤에 올 때만: `inst`, `inst.`, `mr` (뒤에 ver/version이 붙어도 됨)
    ///   예) `Love Dive (Inst.)`, `Song - Instrumental`, `노래 [MR]` → 연주곡 / `Mr. Brightside`, `Instinct` → 해당 없음
    static func matches(_ title: String) -> Bool {
        let token = #"(inst\.?|mr)(\s+(ver\.?|version))?"#
        let patterns = [
            #"\binstrumental\b"#,
            #"[\(\[]\s*"# + token + #"\s*[\)\]]"#,
            #"\s-\s+"# + token + #"\s*$"#,
        ]
        return patterns.contains { title.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil }
    }
}

// MARK: - 앱 전용 저장 폴더

/// Application Support/LiveLyrics/
///   ├─ synced/  싱크 가사(.lrc)
///   └─ plain/   일반 가사(.txt) — 싱크 가사를 못 찾았을 때만
nonisolated enum LyricsStore {
    static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LiveLyrics", isDirectory: true)
    }
    static var syncedDir: URL { root.appendingPathComponent("synced", isDirectory: true) }
    static var plainDir: URL { root.appendingPathComponent("plain", isDirectory: true) }

    /// "아티스트 - 제목" (파일 이름에 못 쓰는 글자는 _ 로). 검색 기록의 키로도 같이 씀
    static func fileName(title: String, artist: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.controlCharacters)
        let name = "\(artist) - \(title)".components(separatedBy: forbidden).joined(separator: "_")
        return String(name.prefix(120))
    }

    private static func syncedURL(_ title: String, _ artist: String) -> URL {
        syncedDir.appendingPathComponent(fileName(title: title, artist: artist) + ".lrc")
    }

    private static func plainURL(_ title: String, _ artist: String) -> URL {
        plainDir.appendingPathComponent(fileName(title: title, artist: artist) + ".txt")
    }

    /// 저장된 곡 이름 목록 ("아티스트 - 제목"), 가나다·알파벳 순. kind는 .synced 또는 .plain 만 의미 있음
    static func savedNames(_ kind: LyricsKind) -> [String] {
        let dir = kind == .synced ? syncedDir : plainDir
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension == (kind == .synced ? "lrc" : "txt") }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
    }

    static func loadSynced(title: String, artist: String) -> LyricsResult? {
        guard let lrc = try? String(contentsOf: syncedURL(title, artist), encoding: .utf8) else { return nil }
        let lines = LRCParser.parse(lrc)
        return lines.isEmpty ? nil : LyricsResult(kind: .synced, lines: lines, lrc: lrc)
    }

    static func loadPlain(title: String, artist: String) -> LyricsResult? {
        guard let text = try? String(contentsOf: plainURL(title, artist), encoding: .utf8), !text.isEmpty else { return nil }
        return LyricsResult(kind: .plain, plain: text)
    }

    /// 싱크 가사는 synced/, 일반 가사는 plain/ 에 저장. 저장했으면 그 폴더 이름을 돌려줌
    @discardableResult
    static func save(_ result: LyricsResult, title: String, artist: String) throws -> String? {
        switch result.kind {
        case .synced:
            try FileManager.default.createDirectory(at: syncedDir, withIntermediateDirectories: true)
            try result.lrc.write(to: syncedURL(title, artist), atomically: true, encoding: .utf8)
            // 싱크 가사를 구했으니 예전에 저장한 일반 가사는 필요 없음
            try? FileManager.default.removeItem(at: plainURL(title, artist))
            return "synced"
        case .plain:
            try FileManager.default.createDirectory(at: plainDir, withIntermediateDirectories: true)
            try result.plain.write(to: plainURL(title, artist), atomically: true, encoding: .utf8)
            return "plain"
        case .instrumental, .none:
            return nil
        }
    }

    // MARK: 검색 기록 (search-log.json)

    private static var searchLogURL: URL { root.appendingPathComponent("search-log.json") }

    static func loadSearchLog() -> [String: SearchRecord] {
        guard let data = try? Data(contentsOf: searchLogURL) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([String: SearchRecord].self, from: data)) ?? [:]
    }

    private static func saveSearchLog(_ log: [String: SearchRecord]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(log) else { return }
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try? data.write(to: searchLogURL, options: .atomic)
    }

    static func searchRecord(title: String, artist: String) -> SearchRecord? {
        loadSearchLog()[fileName(title: title, artist: artist)]
    }

    /// 검색이 끝날 때 기록. 싱크 가사를 찾았으면 기록을 지움 ("못 찾은 곡" 목록에서 자동으로 빠짐)
    static func updateSearchRecord(for result: LyricsResult, title: String, artist: String, album: String, duration: TimeInterval) {
        let key = fileName(title: title, artist: artist)
        var log = loadSearchLog()
        switch result.kind {
        case .synced:
            log[key] = nil
        case .plain, .none, .instrumental:
            let name = result.kind == .plain ? "plain" : (result.kind == .none ? "none" : "instrumental")
            log[key] = SearchRecord(key: key, title: title, artist: artist, album: album, duration: duration,
                                    result: name, searchedAt: Date(), summary: result.summary)
        }
        saveSearchLog(log)
    }

    /// "못 찾은 곡" 목록 (최근 검색한 순)
    static func notFoundRecords() -> [SearchRecord] {
        loadSearchLog().values.filter { $0.result == "none" }.sorted { $0.searchedAt > $1.searchedAt }
    }

    // MARK: 삭제

    /// 저장 파일 이름(= 기록 키)으로 삭제: kind가 .synced면 synced/, .plain이면 plain/ 파일, .none이면 기록만. 검색 기록은 항상 같이 지움
    static func delete(_ kind: LyricsKind, name: String) {
        switch kind {
        case .synced: try? FileManager.default.removeItem(at: syncedDir.appendingPathComponent(name + ".lrc"))
        case .plain: try? FileManager.default.removeItem(at: plainDir.appendingPathComponent(name + ".txt"))
        case .instrumental, .none: break
        }
        var log = loadSearchLog()
        if log[name] != nil {
            log[name] = nil
            saveSearchLog(log)
        }
    }
}

/// 다음 곡 가사 미리 받기 판단 (작업 021)
nonisolated enum LyricsPrefetch {
    /// 기억해 둘 미리 받은 곡 수
    static let memory = 20

    /// 다음 곡 key가 비어 있지 않고, 지금 곡과 다르고(반복 재생 등), 이미 시도한 곡이 아니면 true
    static func shouldPrefetch(nextKey: String, currentKey: String?, tried: Set<String>) -> Bool {
        !nextKey.isEmpty && nextKey != currentKey && !tried.contains(nextKey)
    }
}

// MARK: - LRCLIB 검색

nonisolated enum LyricsService {
    private struct Record: Decodable {
        let duration: Double?
        let syncedLyrics: String?
        let plainLyrics: String?
        let instrumental: Bool?
    }

    /// 싱크 가사를 최대한 찾아본다. 앞 단계에서 싱크 가사를 찾으면 멈추고,
    /// 일반 가사만 나오면 다음 단계까지 계속 검색해서 싱크 가사를 먼저 찾아본다.
    /// 모든 단계에서 곡 길이 차이는 10초 이내만 채택. 네트워크 오류는 throw
    /// fast: true면 1단계(get)와 2단계(원래 제목 검색) 요청을 동시에 보냄 (작업 021, 지금 재생 중인 곡용).
    ///       결과는 지금과 같은 순서(1단계 → 2단계 → 3·4단계 차례로)로 판단. 1단계에서 찾으면 2단계 요청은 취소
    static func find(title: String, artist: String, album: String, duration: TimeInterval,
                     fast: Bool = false) async throws -> LyricsResult {
        var plain: LyricsResult?        // 싱크를 못 찾았을 때 쓸 일반 가사 후보
        var isInstrumental = false
        var noResultStages: [Int] = []  // 결과가 아예 없던 단계 (못 찾은 곡 요약용)
        var otherNotes: [String] = []   // 후보는 있었지만 쓸 수 없던 이유 (요약용)

        /// 후보 중 곡 길이가 가장 가까운 순으로 보고, 싱크 가사가 있으면 결과로 돌려줌.
        /// 없으면 일반 가사·연주곡 여부만 기억해 둠
        func consider(_ records: [Record], stage: Int, name: String) -> LyricsResult? {
            let candidates = records
                .map { (record: $0, gap: abs(($0.duration ?? .infinity) - duration)) }
                .filter { $0.gap <= 10 }
                .sorted { $0.gap < $1.gap }
                .map(\.record)

            for record in candidates {
                if let lrc = record.syncedLyrics, !lrc.isEmpty {
                    let lines = LRCParser.parse(lrc)
                    if !lines.isEmpty {
                        return LyricsResult(kind: .synced, lines: lines, lrc: lrc, stage: stage, stageName: name)
                    }
                }
            }
            if plain == nil,
               let text = candidates.compactMap(\.plainLyrics).first(where: { !$0.isEmpty }) {
                plain = LyricsResult(kind: .plain, plain: text, stage: stage, stageName: name)
            }
            if candidates.contains(where: { $0.instrumental == true }) { isInstrumental = true }

            // 이 단계에서 쓸 수 있는 싱크 가사가 없던 이유를 기록
            if records.isEmpty {
                noResultStages.append(stage)
            } else if candidates.isEmpty {
                otherNotes.append("\(stage)단계 후보 \(records.count)개 — 길이 차이 10초 초과")
            } else {
                otherNotes.append("\(stage)단계 후보 \(candidates.count)개 — 싱크 가사 없음")
            }
            return nil
        }

        // fast면 2단계(원래 제목 검색)를 미리 보내 둠. 판단은 아래에서 차례대로
        let earlySearch: Task<Data?, Error>? = fast
            ? Task { try await request("search", ["track_name": title, "artist_name": artist]) }
            : nil
        defer { earlySearch?.cancel() }   // 1단계에서 찾았거나 오류로 끝나면 남은 요청 취소

        // 1단계: 원래 제목·아티스트·앨범·길이로 정확히 조회
        let exact = try await request("get", [
            "track_name": title, "artist_name": artist,
            "album_name": album, "duration": String(Int(duration.rounded())),
        ])
        if let data = exact, let record = try? JSONDecoder().decode(Record.self, from: data) {
            if let found = consider([record], stage: 1, name: "원래 조회") { return found }
        } else {
            noResultStages.append(1)
        }

        // 2~4단계: 검색 (같은 검색어는 건너뜀)
        let cleaned = TitleCleaner.clean(title)
        let searches = [
            (name: "원래 제목 검색", title: title, artist: artist),
            (name: "정리한 제목", title: cleaned, artist: artist),
            (name: "정리한 제목 + 첫 아티스트", title: cleaned, artist: TitleCleaner.firstArtist(artist)),
        ]
        var tried = Set<String>()
        for (index, search) in searches.enumerated() {
            guard tried.insert(search.title + "\n" + search.artist).inserted else { continue }
            let response: Data?
            if index == 0, let earlySearch {
                response = try await earlySearch.value   // fast: 미리 보낸 2단계 결과
            } else {
                response = try await request("search", ["track_name": search.title, "artist_name": search.artist])
            }
            guard let data = response,
                  let records = try? JSONDecoder().decode([Record].self, from: data) else {
                noResultStages.append(index + 2)
                continue
            }
            if let found = consider(records, stage: index + 2, name: search.name) { return found }
        }

        // 싱크 가사를 못 찾음 → 일반 가사 > 연주곡 > 없음. 시도한 단계의 요약을 같이 돌려줌
        var parts: [String] = []
        if !noResultStages.isEmpty {
            let stages = noResultStages.sorted()
            parts.append(stages.count > 1 ? "\(stages[0])~\(stages[stages.count - 1])단계 결과 없음" : "\(stages[0])단계 결과 없음")
        }
        parts += otherNotes
        // LRCLIB의 instrumental 표시는 믿지 않음: 가사가 없는 곡에 "연주곡" 표시가 잘못 붙은 기록이 많아서(예: 에픽하이 - One)
        // 못 찾은 곡으로 취급하고, 연주곡은 제목 규칙(InstrumentalTitle)으로만 거름. 다만 요약에는 표시 사실을 남김
        if plain == nil, isInstrumental { parts.append("LRCLIB이 연주곡으로 표시(가사 없음) — 무시함") }
        var result = plain ?? LyricsResult(kind: .none)
        result.summary = parts.joined(separator: " · ")
        return result
    }

    /// 404(없음)는 nil, 그 외 오류는 throw
    private static func request(_ path: String, _ query: [String: String]) async throws -> Data? {
        var components = URLComponents(string: "https://lrclib.net/api/\(path)")
        components?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components?.url else { return nil }

        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("LiveLyricsExperiment (personal use)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return nil }
        // 서버가 응답한 요청만 센다 (상태 코드 무관, 취소·오프라인으로 throw되면 세지 않음)
        LrclibUsage.record(path == "get" ? .get : .search)
        if http.statusCode == 404 { return nil }
        guard (200..<300).contains(http.statusCode) else { throw LyricsError.http(http.statusCode) }
        return data
    }
}
