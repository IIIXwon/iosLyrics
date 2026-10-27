# Live Lyrics (iOS)

Spotify에서 재생 중인 곡의 **싱크 가사를 아이폰 잠금화면(Live Activity) 카드에 표시**하는 개인용 앱.
유료 앱 Dynamic Lyrics 대체가 목표. App Store 배포 없음 (무료 계정으로 개인 사이드로딩).

- 대화·주석·로그·UI 문구는 **한국어**
- 사용자는 iOS 개발 초보 → 변경 이유를 쉽게 설명하고, Xcode 설정 변경은 **클릭 경로까지** 안내

---

## WHAT — 스택과 코드 지도

- Swift / SwiftUI / ActivityKit(Live Activity) / WidgetKit / CoreLocation, **최소 iOS 16.4**
- 외부: Spotify Web API (PKCE 로그인, 개발자 모드) · LRCLIB (가사 조회 전용)
- 서버·패키지 매니저 없음. 가사·토큰은 기기 안에만 보관

**앱 타깃 `LiveLyricsExperiment`**
| 파일 | 하는 일 |
|---|---|
| `LiveLyricsExperimentApp.swift` | 진입점, `ExperimentController`를 environmentObject로 주입 |
| `ContentView.swift` | 로그인, 현재 재생, 시작/정지, 로그 화면 |
| `ExperimentController.swift` | 전체 조율: Live Activity 시작·갱신·종료, 로그 |
| `LyricsService.swift` | LRCLIB 4단계 검색 + LRC 파싱 + 현재 줄 계산 + 앱 전용 저장 폴더(`LyricsStore`: `synced/`·`plain/`) |
| `LocationKeepAlive.swift` | 백그라운드 유지용 저전력 위치 추적 + `BatteryMeter` |
| `Spotify/SpotifyConfig.swift` | Client ID, Redirect URI `livelyrics://callback`, scopes |
| `Spotify/SpotifyAuth.swift` | PKCE 로그인, 토큰 갱신, 키체인(`AfterFirstUnlock`) 저장 |
| `Spotify/SpotifyAPI.swift` | currently-playing 조회, 401 재시도, 429 Retry-After |
| `Spotify/NowPlayingService.swift` | 폴링(재생 중 3초·일시정지 15초·곡 없음 10초), 곡 변경·일시정지·seek 감지, 위치 추정 |

**위젯 확장 타깃 `LyricsWidgetExtension`**
| 파일 | 하는 일 |
|---|---|
| `LyricsWidgetBundle.swift` | 위젯 진입점 |
| `LyricsLiveActivity.swift` | 잠금화면 카드, 다이내믹 아일랜드 UI, `PlaybackTimeRow` |

**두 타깃 공유** ⚠️ Target Membership 둘 다 체크
- `LyricsActivityAttributes.swift` — 앱 ↔ 위젯 사이의 데이터 계약(`ContentState`)

## WHY — 각 부분이 존재하는 이유 (수정 범위 판단용)

- **`LocationKeepAlive`**: 앱이 잠금 상태에서도 카드를 갱신하려면 백그라운드에 살아 있어야 하는데, 실험상 **위치 추적만 통과**했다. 제거·대체 금지
- **`ExperimentController`**: 카드 갱신의 **유일한 창구**. `Activity.update`는 여기서만, 바뀐 게 있을 때만 호출
- **`NowPlayingService`**: 폴링 사이의 위치를 추정해 `trackStart`만 넘긴다. 카드의 시간·진행바는 iOS가 `timerInterval`로 스스로 흘린다 → 매초 갱신하지 말 것
- **`LyricsActivityAttributes`**: 필드를 바꾸면 앱·위젯 **양쪽**이 영향받음. 반드시 둘 다 같이 수정
- **잠금화면 카드 중심**: 다이내믹 아일랜드는 Spotify 표시가 우선이라 거의 안 보임

## ⛔ 다시 시도하지 말 것 (상세: `docs/plan/constraints.md`)

- 무음 오디오로 백그라운드 유지 → 약 30초 후 iOS가 갱신 거부 (관련 코드 `SilentAudioKeepAlive`는 삭제함, 다시 만들지 말 것)
- 푸시(APNs) 기반 갱신 → 무료 계정이라 불가
- `NSSupportsLiveActivitiesFrequentUpdates` → 로컬 갱신엔 효과 없음
- 번역 기능, 로컬 LRC → 사용자가 하지 않기로 결정
- LRCLIB 외 가사 출처(Spotify 내부 API, 비공식 API) · 싱크 자동 생성 → 약관 위반 또는 기술적으로 불가

## HOW — 작업 방식

Claude Code 메인 세션(리드)이 서브에이전트 `qa`, `ios-dev`를 불러 작업한다. 흐름은 `/task N` → 사용자 아이폰 확인 → `/judge N` (아래 "🔁 작업 흐름").

### 역할
| 에이전트 | 하는 일 | 수정 범위 |
|---|---|---|
| 리드(메인 세션) | 지시서 작성, 거절 판정, `/code-review` 실행, 최종 테스트·빌드, git/PR, Xcode 클릭 경로 안내 | 계약(아래), `docs/plan/**`, `.claude/**`, `scripts/**` |
| `qa` | 테스트 모드: 지시서의 Red 목록만큼 단위 테스트 작성·실행, 실패를 피드백으로 정리 / 로그 모드: 아이폰 로그를 확인 항목과 대조해 판정 근거 | `LiveLyricsTests/**` |
| `ios-dev` | 지시서대로 개발·빌드, 피드백을 수용하거나 근거를 붙여 거절, 보고서 작성 | `LiveLyricsExperiment/**`, `Spotify/**`, `LyricsWidget/**`(Info.plist 제외), `docs/dev/**` |

- 서브에이전트끼리는 직접 대화하지 않는다. QA 피드백 → 리드 → 개발, 개발의 거절 → **리드가 지시서 기준으로 판정**
- 개발은 테스트를 수정·삭제·비활성화하지 않는다. 서브에이전트는 git을 다루지 않는다
- 서브에이전트는 파일을 Edit/Write로만 쓴다 (Bash heredoc 금지)
- 지시서와 다르게 해야 하면 임의로 정하지 말고 보고서 "남은 이슈·질문"에 남기고 멈춘다
- 보고 형식: `## 변경 파일` / `## 검증(명령과 결과)` / `## 남은 이슈·질문` (에이전트별 세부 형식은 `.claude/agents/`)

### 계약 (리드만 수정)
| 파일 | 역할 |
|---|---|
| `LyricsActivityAttributes.swift` | 앱 ↔ 위젯 데이터 계약(`ContentState`). 바꾸면 양쪽 모두 영향 |
| `LiveLyricsExperiment/Info.plist`, `LyricsWidget/Info.plist`, `LiveLyricsExperiment.xcodeproj` | 권한, Background Modes, 타깃·빌드 설정 |
| `docs/plan/**` | 지시서, roadmap, decisions, constraints |

다른 역할은 계약을 읽기만 한다. 바꿔야 하면 근거(파일:줄)와 함께 리드에게 보고한다.

### 명령
| 목적 | 명령 |
|---|---|
| 빌드(컴파일 확인) | `xcodebuild -project LiveLyricsExperiment.xcodeproj -scheme LiveLyricsExperiment -destination 'generic/platform=iOS' -quiet build` (서명 오류면 끝에 `CODE_SIGNING_ALLOWED=NO`) |
| 단위 테스트 | `xcodebuild -project LiveLyricsExperiment.xcodeproj -scheme LiveLyricsExperiment -destination 'platform=iOS Simulator,name=iPhone 18' -quiet test` |
| 시뮬레이터 이름 확인 | `xcrun simctl list devices available` |
| 규칙·Client ID 점검 | `scripts/check.sh` |

> 테스트 타깃 `LiveLyricsTests` 추가 후 첫 `/task`에서 리드가 두 명령을 실제로 돌려 보고 이 표를 확정한다 (시뮬레이터 기기 이름, 위젯 확장까지 함께 빌드되는지).

- **아이폰 실행·동작 확인은 사용자가** 실기기에서 한다. 테스트 통과 ≠ 동작 확인이므로 실기기에서 볼 항목을 알려 준다
- 결과 확인: 사용자가 앱의 [전체 복사] 로그를 붙여 줌. 잠금 상태 확인은 Mac 콘솔 앱에서 `liveactivitiesd` 로그
- 배터리 측정은 충전기를 뺀 상태에서

### 테스트 규칙
- 단위 테스트(Swift Testing, 타깃 `LiveLyricsTests`)는 **순수 로직만**: LRC 파싱, 현재 줄 계산, 제목 정리·연주곡 제목 판단, 재검색 간격, 호출 수·한도 판단, 권한 판단 등
- 기기 동작(잠금화면 카드, 백그라운드 유지, 카드 ▶︎·탭, 실제 Spotify 응답)은 **아이폰 확인**으로 본다. UI 테스트(XCUITest)는 쓰지 않는다
- 이름은 한글 `행동_조건_결과`, 본문은 `// given // when // then`. 실제 네트워크·위치·키체인·UserDefaults 값은 쓰지 않는다
- Red: 기존 함수는 assertion 실패여야 한다. 새 함수는 지시서에 시그니처가 있을 때만 "없는 이름" 컴파일 에러를 Red로 인정한다

### Git
- `main`은 PR + squash merge로만 바꾼다. main 직접 push는 hook으로 차단한다
- 브랜치 `task/<번호>-<이름>`. 커밋 메시지는 Conventional Commits (`docs(plan): 011 지시서`, `test(lyrics): ... (Red)`, `feat(lyrics): ...`, `fix(lyrics): 리뷰 반영`)
- push, PR 생성, merge 전에는 사용자 확인을 받는다. git은 리드만 다룬다
- `git add`는 파일 이름으로만 한다(`-A`, `.`, `commit -a` 금지). 커밋 전에 `scripts/check.sh`
- ⚠️ **Spotify Client ID는 외부 노출 금지, 로컬에서만 사용**: `Spotify/SpotifyConfig.swift`의 Client ID 변경과 `Spotify/SpotifySecrets.swift`는 커밋·PR·보고서·로그 인용에 넣지 않는다

### 코딩 규칙 / 자주 난 오류
- 클래스는 `@MainActor`, 델리게이트 메서드는 `nonisolated` + `Task { @MainActor in ... }`
- `ObservableObject`를 쓰는 파일은 **`import Combine`** 필수 (없으면 conform 오류)
- 공유 struct는 `nonisolated struct` (Swift 6 기본 MainActor 격리 대응)
- `Float`와 `Double`을 섞어 계산하지 말 것 (배터리 잔량은 `Float`)
- 파일 추가 시 같은 이름 중복 금지 ("already exists", "Invalid redeclaration" 경험)
- 시간 계산은 `ProcessInfo.processInfo.systemUptime` 기준, 카드용 Date는 `Date() - position`
- 로그는 `ExperimentController.log()`로, 이모지 접두어로 구분 (✅ ❌ ⚠️ 🎵 🪪 💓 📍 등)

### 법적 규칙 (개인용 전제)
- LRCLIB 가사는 **조회만**. 서버 저장·재배포·업로드 자동화 금지, 캐시는 기기 안에만
- 앱 이름·아이콘에 "Spot"/Spotify 상표 사용 금지. Spotify 개발자 모드는 상업적 이용 불가

---

## 📂 필요할 때만 읽는 문서 (JIT)

아래 문서는 **해당 작업을 할 때만** 열어서 읽는다. 처음부터 전부 읽지 말 것.

| 이런 작업이면 | 먼저 읽을 문서 |
|---|---|
| 지금 맡은 작업 내용 | `docs/plan/tasks/`의 해당 지시서 |
| 백그라운드 유지·갱신 방식·배터리, "다른 방법은 없나?" 검토 | `docs/plan/constraints.md` |
| 다음 할 일, 우선순위, 결정 이유 | `docs/plan/roadmap.md`, `docs/plan/decisions.md` |
| 데이터 흐름, 카드 갱신 조건, `ContentState`, 가사 로직 | `docs/dev/architecture.md` |
| Info.plist, Background Modes, Deployment Target, Spotify 대시보드 | `docs/dev/xcode-setup.md` |
| 이전 작업·테스트 결과 | `docs/dev/reports/`, `docs/plan/roadmap.md` (2026-10 이전 기록은 `docs/dev/archive/`) |

## 🔁 작업 흐름
- **`/task N`**: ① 리드 지시서·브랜치 → ② `qa` 테스트 작성(Red) → ③ `ios-dev` 개발 → ④ `qa` 테스트 실행 → ⑤ 리드 확인 + `/code-review` → ⑥ 아이폰 확인 항목을 알려 주고 멈춤
  - ④ 실패·⑤ 지적 → `ios-dev`가 항목마다 수용(수정 후 ④) 또는 거절(리드 판정: 테스트 틀림 → `qa` / 지시서 모호 → 리드 / 개발 틀림 → `ios-dev`)
  - Red 목록이 "없음"이면 ②④를 건너뛴다. 피드백 루프가 3번을 넘으면 사용자에게 묻는다
- **`/judge N`**: 사용자가 붙인 로그 → `qa` 로그 모드로 근거 정리 → 리드 판정 → 통과(지시서 `완료`, roadmap·decisions 갱신, PR) 또는 "검토 N차 — 수정 요청" → `/task N`
- 세부 단계: `.claude/skills/task/SKILL.md`, `.claude/skills/judge/SKILL.md`
- 지시서·보고서 형식: `docs/plan/tasks/README.md`

## 📝 문서 관리
- `docs/plan/` : 리드가 작성·수정 (지시서, roadmap, decisions, constraints). 지시서 상태 줄은 리드만 바꾼다
- `docs/dev/` : `ios-dev`가 작성·수정 (architecture, xcode-setup, reports/)
- `docs/dev/archive/` : 이전 구조(Claude 앱 → Xcode Agent) 시절 기록. 더는 갱신하지 않는다
- `CLAUDE.md` : 리드만 수정
