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

- **컴파일 확인은 Claude가 Xcode 도구(`BuildProject`)로 직접** 한다. 코드를 바꿨으면 빌드해서 오류 없음을 확인한 뒤 보고
- **아이폰 실행·동작 테스트는 사용자가** (시뮬레이터 X, 자동 테스트 없음). 빌드 통과 ≠ 동작 확인이므로, 실기기에서 볼 항목을 알려 준다
- 아래 코딩 규칙은 자주 났던 오류를 미리 막기 위한 것
- 결과 확인: 사용자가 앱의 [전체 복사] 로그를 붙여 줌. 잠금 상태 확인은 Mac 콘솔 앱에서 `liveactivitiesd` 로그
- 배터리 측정은 충전기를 뺀 상태에서
- 작업을 마치면 `docs/dev/progress.md`의 체크리스트·테스트 결과를 갱신

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
| 이전 작업·테스트 수치 | `docs/dev/progress.md` |

## 🔁 작업 흐름 (지시서 → 보고서)
사용자가 **"다음 작업 진행해"**라고 하면:
1. `docs/plan/tasks/`에서 상태가 `대기` 또는 `수정 요청`인 지시서 중 **번호가 가장 작은 것**을 연다 (`README.md` 제외)
2. 지시서대로 작업하고 BuildProject로 빌드 확인. `수정 요청`이면 지시서 맨 아래 "검토 N차" 내용만 반영
3. `docs/dev/reports/NNN-report.md`에 보고서 작성 (같은 번호, 상태: `검토 요청`). 형식은 `docs/plan/tasks/README.md` 참고
4. 지시서와 다르게 해야 하면 임의로 정하지 말고 보고서의 "질문"에 남기고 멈춘다
5. 사용자에게 보고서 요약과 **아이폰에서 확인할 항목**을 알려 준다
- 처리할 지시서가 없으면 "대기 중인 지시서가 없어요"라고 답한다
- 지시서의 상태 줄은 Agent가 바꾸지 않는다 (Claude 앱이 검토 후 변경)

## 📝 문서 권한
- `docs/dev/` : Agent가 작성·수정 (architecture, xcode-setup, progress, feedback, reports/)
- `docs/plan/` : 계획 담당(Claude 앱) 문서. **읽기만, 수정 금지**
- `CLAUDE.md` : 수정 금지. 바꿀 게 있으면 `docs/dev/feedback.md`에 제안
- 계획과 다르게 해야 하면 임의로 바꾸지 말고 `feedback.md`에 남길 것
