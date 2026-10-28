// 앱 타깃 — 메인 화면: 준비 상태, Spotify 로그인, 싱크 보정, 시작/정지, 저장된 가사
// 로그·조회 설정은 맨 아래 [개발자 메뉴]로 옮겼어요 (로그 기록은 계속 쌓음)
import AuthenticationServices
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var controller: ExperimentController
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession

    var body: some View {
        NavigationStack {
            Form {
                ReadinessSection(model: controller.readiness) { fix in handle(fix) }

                SpotifySection(auth: controller.auth) {
                    Task { await controller.login(using: webAuthenticationSession) }
                } onLogout: {
                    controller.logout()
                }

                Section {
                    Stepper(value: $controller.syncOffset, in: -5...5, step: 0.25) {
                        LabeledContent("싱크 보정", value: String(format: "%+.2f초", controller.syncOffset))
                    }
                } footer: {
                    Text("카드 시간이 Spotify보다 늦으면 + 로, 빠르면 - 로 맞추세요. 추적 중에도 바로 반영돼요.")
                }

                StartStopSection(
                    auth: controller.auth,
                    readiness: controller.readiness,
                    isRunning: controller.isRunning,
                    onStart: { controller.start() },
                    onStop: { controller.stop() }
                )

                SavedLyricsSection()

                Section {
                    NavigationLink("개발자 메뉴") { DeveloperMenuView() }
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Live Lyrics")
        }
        // 앱을 처음 열 때: 준비가 모두 ✅이고 사용자가 정지해 두지 않았다면 자동 시작
        .task { await controller.autoStartIfNeeded() }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .background: controller.log("📱 백그라운드로 이동")
            case .active:
                controller.log("📱 앱 화면으로 복귀")
                controller.readiness.refresh()   // 설정 앱에서 바꾸고 돌아왔을 수 있어서 준비 상태를 다시 확인
                Task { await controller.autoStartIfNeeded() }
            default: break
            }
        }
        // 잠금화면 카드 탭(livelyrics://open-spotify) → Spotify 열기 (작업 009·010)
        .onOpenURL { controller.handleOpenURL($0) }
    }

    /// 준비 상태의 [해결] 버튼이 하는 일
    private func handle(_ fix: ReadinessItem.Fix) {
        switch fix {
        case .openSettings:
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        case .requestLocation:
            controller.location.requestPermission()
        }
    }
}

// MARK: - 개발자 메뉴 (로그 · 조회 설정)

private struct DeveloperMenuView: View {
    @EnvironmentObject private var controller: ExperimentController
    @State private var copied = false

    var body: some View {
        Form {
            Section("조회") {
                IntervalPicker(service: controller.nowPlaying)
                    .disabled(controller.isRunning)
                Button("한 번 조회해 보기") { controller.checkOnce() }
                    .disabled(controller.isRunning || !controller.auth.isLoggedIn)
            }

            // 부모가 다시 그려질 때(로그 추가 등) 값을 새로 계산해 넘김 → 메뉴를 열어 둔 동안에도 숫자가 갱신됨
            Section {
                UsageRow(title: "오늘", total: APIUsage.total(daysAgo: 0), summary: APIUsage.summary(daysAgo: 0))
                UsageRow(title: "어제", total: APIUsage.total(daysAgo: 1), summary: APIUsage.summary(daysAgo: 1))
                if let until = SpotifyBlock.until {
                    Text("⛔️ 한도 차단 중 — \(SpotifyBlock.untilText(until)) 이후 재개")
                        .font(.caption).foregroundStyle(.red)
                }
            } header: {
                Text("Spotify 호출 수")
            } footer: {
                Text("Spotify Web API를 실제로 보낸 횟수예요 (LRCLIB 제외). 한도 초과가 있었는지 확인할 때 쓰세요.")
            }

            Section {
                UsageRow(title: "오늘", total: LrclibUsage.total(daysAgo: 0), summary: LrclibUsage.summary(daysAgo: 0))
                UsageRow(title: "어제", total: LrclibUsage.total(daysAgo: 1), summary: LrclibUsage.summary(daysAgo: 1))
            } header: {
                Text("LRCLIB 호출 수")
            } footer: {
                Text("가사 서버(LRCLIB)에 실제로 보낸 횟수예요. 한도는 1분에 약 90회예요.")
            }

            Section {
                ForEach(controller.logs, id: \.self) { line in
                    Text(line).font(.caption.monospaced())
                }
            } header: {
                HStack {
                    Text("로그 (최신순)")
                    Spacer()
                    Button(copied ? "복사됨" : "전체 복사") {
                        UIPasteboard.general.string = controller.logText
                        copied = true
                    }
                    .font(.caption)
                    .textCase(nil)
                }
            }
        }
        .navigationTitle("개발자 메뉴")
        .onAppear { copied = false }
    }
}

// MARK: - Spotify 로그인 영역
// SpotifyButton(버튼 판단)은 Logic/AppButtons.swift로 옮김 (작업 024)

private struct SpotifySection: View {
    @ObservedObject var auth: SpotifyAuth
    let onLogin: () -> Void
    let onLogout: () -> Void

    var body: some View {
        Section("Spotify") {
            // 로그아웃 버튼이 보이면 로그인 상태라는 뜻이라 상태 줄은 따로 두지 않아요 (작업 018)
            switch SpotifyButton.make(isLoggedIn: auth.isLoggedIn, isConfigured: SpotifyConfig.isConfigured) {
            case .logout:
                Button("로그아웃", role: .destructive, action: onLogout)
            case .login(let enabled):
                Button("Spotify로 로그인", action: onLogin)
                    .disabled(!enabled)
            }
        }
    }
}

// MARK: - 시작/정지
// StartButton(버튼 상태 판단)은 Logic/AppButtons.swift로 옮김 (작업 024)

/// auth·readiness를 직접 관찰해서 로그인/로그아웃하자마자 [시작] 상태가 바뀌도록 따로 뺀 칸
private struct StartStopSection: View {
    @ObservedObject var auth: SpotifyAuth
    @ObservedObject var readiness: ReadinessModel
    let isRunning: Bool
    let onStart: () -> Void
    let onStop: () -> Void

    var body: some View {
        Section {
            if isRunning {
                Button("정지", role: .destructive, action: onStop)
            } else {
                let start = StartButton.make(isLoggedIn: auth.isLoggedIn, hasProblem: readiness.hasProblem)
                // 위치 권한 등 다른 항목이 ❌여도 막지는 않음 (시작할 때 필요한 것을 다시 확인함)
                Button("시작", action: onStart)
                    .disabled(!start.enabled)
                if let hint = start.hint {
                    Text(hint)
                        .font(.caption).foregroundStyle(.orange)
                }
            }
        } footer: {
            Text("앱을 열면 준비가 돼 있을 때 자동으로 시작해요. [정지]를 누르면 [시작]을 다시 누를 때까지 자동으로 시작하지 않아요.")
        }
    }
}

// MARK: - 준비 상태 (작업 004)
// 항상 닫힌 상태가 기본이고, 사용자가 눌렀을 때만 펼쳐요 (저절로 펼치지 않음, 작업 018 검토 1차).
// 라벨은 3단계: 전부 ✅ → "✅ 준비 완료" / ✅·❌ 섞임 → "⚠️ 준비가 덜 됐어요 (n개)" / 전부 ❌ → "❌ 준비가 안 됐어요 (n개)"

private struct ReadinessSection: View {
    @ObservedObject var model: ReadinessModel
    let onFix: (ReadinessItem.Fix) -> Void
    @State private var expanded = false   // 기본은 닫힘

    var body: some View {
        Section {
            DisclosureGroup(isExpanded: $expanded) {
                ForEach(model.items) { item in
                    ReadinessRow(item: item, onFix: onFix)
                }
            } label: {
                switch ReadinessRules.summary(model.items) {
                case .ready:
                    Text("✅ 준비 완료").font(.headline)
                case .partial(let problems):
                    Text("⚠️ 준비가 덜 됐어요 (\(problems)개)")
                        .font(.headline).foregroundStyle(.orange)
                case .notReady(let problems):
                    Text("❌ 준비가 안 됐어요 (\(problems)개)")
                        .font(.headline).foregroundStyle(.red)
                }
            }
        } header: {
            Text("준비 상태")
        }
    }
}

private struct ReadinessRow: View {
    let item: ReadinessItem
    let onFix: (ReadinessItem.Fix) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(item.isReady ? "✅" : "❌")
                Text(item.title).fontWeight(item.isReady ? .regular : .semibold)
                Spacer()
                if item.isReady, let detail = item.okDetail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            if let problem = item.problem {
                Text(problem).font(.caption).foregroundStyle(.red)
            }
            if let hint = item.hint {
                Text(hint).font(.caption).foregroundStyle(.secondary)
            }
            if let fix = item.fix, let title = item.fixTitle {
                Button(title) { onFix(fix) }
                    .buttonStyle(.borderless)
                    .font(.caption.bold())
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 저장된 가사 (아이폰 안의 앱 전용 폴더 LiveLyrics/synced, LiveLyrics/plain)

private struct SavedLyricsSection: View {
    @EnvironmentObject private var controller: ExperimentController
    @State private var syncedCount = 0
    @State private var plainCount = 0
    @State private var notFoundCount = 0

    var body: some View {
        Section {
            NavigationLink {
                SavedLyricsListView()
            } label: {
                LabeledContent("싱크 / 일반 / 못 찾음", value: "\(syncedCount)곡 / \(plainCount)곡 / \(notFoundCount)곡")
            }
        } header: {
            Text("저장된 가사")
        }
        .onAppear(perform: refresh)
        // 가사를 저장·삭제했거나 검색 결과가 기록되면 개수를 다시 셈
        .onChange(of: controller.logs.first) { line in
            guard let line else { return }
            if ["💾", "🗑", "🎵 가사 찾음", "⚠️ 가사 없음"].contains(where: { line.contains($0) }) { refresh() }
        }
    }

    private func refresh() {
        syncedCount = LyricsStore.savedNames(.synced).count
        plainCount = LyricsStore.savedNames(.plain).count
        notFoundCount = LyricsStore.notFoundRecords().count
    }
}

private struct SavedLyricsListView: View {
    @EnvironmentObject private var controller: ExperimentController
    @State private var synced: [String] = []
    @State private var plain: [String] = []
    @State private var notFound: [SearchRecord] = []
    @State private var records: [String: SearchRecord] = [:]   // 일반 가사 곡의 검색 기록 (있는 것만)
    @State private var copied = false

    var body: some View {
        List {
            Section("싱크 가사 (\(synced.count))") {
                if synced.isEmpty { Text("없음").foregroundStyle(.secondary) }
                ForEach(synced, id: \.self) { SongRow(title: $0, record: nil) }
                    .onDelete { delete($0, kind: .synced) }
            }
            Section("일반 가사만 있는 곡 — 싱크 없음 (\(plain.count))") {
                if plain.isEmpty { Text("없음").foregroundStyle(.secondary) }
                ForEach(plain, id: \.self) { SongRow(title: $0, record: records[$0]) }
                    .onDelete { delete($0, kind: .plain) }
            }
            Section("못 찾은 곡 (\(notFound.count))") {
                if notFound.isEmpty { Text("없음").foregroundStyle(.secondary) }
                ForEach(notFound, id: \.key) { SongRow(title: "\($0.artist) - \($0.title)", record: $0) }
                    .onDelete { delete($0, kind: .none) }
            }
            Section {
                Button(copied ? "복사됨" : "목록 복사") {
                    UIPasteboard.general.string = copyText()
                    copied = true
                }
            } footer: {
                Text("못 찾은 곡과 일반 가사만 있는 곡 전체를 텍스트로 복사해요. 밀어서 삭제하면 저장된 파일과 검색 기록이 함께 지워지고, 그 곡은 다음에 재생할 때 다시 검색해요.")
            }
        }
        .navigationTitle("저장된 가사")
        .onAppear(perform: reload)
    }

    private func reload() {
        synced = LyricsStore.savedNames(.synced)
        plain = LyricsStore.savedNames(.plain)
        notFound = LyricsStore.notFoundRecords()
        records = LyricsStore.loadSearchLog()
        copied = false
    }

    /// 밀어서 삭제: 저장 파일과 검색 기록을 함께 지움
    private func delete(_ offsets: IndexSet, kind: LyricsKind) {
        let names: [String]
        switch kind {
        case .synced: names = offsets.map { synced[$0] }
        case .plain: names = offsets.map { plain[$0] }
        default: names = offsets.map { notFound[$0].key }
        }
        for name in names {
            LyricsStore.delete(kind, name: name)
            controller.log("🗑 저장된 가사 삭제: \(name)")
        }
        reload()
    }

    /// 계획 쪽 분석용 텍스트 (못 찾은 곡 + 일반 가사만 있는 곡)
    private func copyText() -> String {
        func line(_ r: SearchRecord) -> String {
            let when = r.searchedAt.formatted(date: .abbreviated, time: .shortened)
            return "\(r.artist) - \(r.title) | 앨범: \(r.album) | 길이: \(NowPlayingService.time(r.duration)) | 마지막 검색: \(when) | \(r.summary)"
        }
        var parts = ["[못 찾은 곡 \(notFound.count)]"] + notFound.map(line)
        parts += ["", "[일반 가사만 있는 곡 \(plain.count)]"]
        parts += plain.map { name in records[name].map(line) ?? name }
        return parts.joined(separator: "\n")
    }
}

/// 곡 한 줄: 이름, (기록이 있으면) 앨범 · 길이 · 마지막 검색, 검색 결과 요약
private struct SongRow: View {
    let title: String
    let record: SearchRecord?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            if let record {
                Text("\(record.album) · \(NowPlayingService.time(record.duration)) · 마지막 검색 \(record.agoText)")
                    .font(.caption).foregroundStyle(.secondary)
                if !record.summary.isEmpty {
                    Text(record.summary).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// 하루 호출 수 한 줄: "오늘  128회" + 종류별 합계 (Spotify·LRCLIB 공통, 값은 부모가 계산해 넘김)
private struct UsageRow: View {
    let title: String
    let total: Int
    let summary: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            LabeledContent(title, value: "\(total)회")
            Text(summary)
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct IntervalPicker: View {
    @ObservedObject var service: NowPlayingService

    var body: some View {
        Picker("재생 중 조회 간격", selection: $service.interval) {
            Text("2초").tag(2.0)
            Text("3초").tag(3.0)
            Text("5초").tag(5.0)
        }
        .pickerStyle(.segmented)
    }
}
