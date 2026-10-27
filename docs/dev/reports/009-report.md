# 009 보고서 — Spotify iOS SDK 연결 실험 + 카드 탭으로 Spotify 열기

상태: 검토 요청

> 작성: Xcode Agent (개발 담당) · 지시서: `docs/plan/tasks/009-sdk-experiment-card-tap.md`
> 작성일: 2026-10-27

## 한 줄 요약
A(SDK 연결 실험, 기록만)와 B(카드 탭 → Spotify 열기)를 구현했고 BuildProject가 성공했다 (새 파일 경고 0). SDK는 Swift 패키지로 추가했고, **Xcode에서 사용자가 클릭할 단계는 없다**. 대신 아이폰 테스트 전에 **Spotify 대시보드 설정 1곳과 재로그인**이 필요하다 (아래 "테스트 전 준비"). 카드·가사·폴링·백그라운드 유지·`idleGrace`·폴링 간격은 바꾸지 않았다.

## A. SDK 연결 실험

### 1. SDK 추가 방법
- 공식 저장소 `spotify/ios-sdk`에 `Package.swift`가 있어서 **Swift Package Manager**로 추가했다 (프레임워크 파일을 직접 복사하는 방법보다 관리가 쉬움)
  - 패키지: `https://github.com/spotify/ios-sdk` · 버전 규칙 "5.0.1 이상, 6.0 미만" · 제품 `SpotifyiOS` → **앱 타깃에만** 연결 (위젯 확장에는 연결 안 함)
  - Agent가 프로젝트 파일(`project.pbxproj`)에 직접 넣고 `xcodebuild -resolvePackageDependencies`로 받아지는 것까지 확인 (`SpotifyiOS @ 5.0.1`)
- **사용자 클릭 단계: 없음.** 확인만 하고 싶다면:
  - Xcode 왼쪽 파일 목록 맨 위 파란 아이콘 **LiveLyricsExperiment** 클릭 → 가운데 화면의 **PROJECT → LiveLyricsExperiment** → **Package Dependencies** 탭 → `ios-sdk` 한 줄
  - 왼쪽 파일 목록 맨 아래 **Package Dependencies → SpotifyiOS 5.0.1**
- (참고) Xcode가 "Package resolution failed" 같은 안내를 띄우면: 메뉴 **File → Packages → Reset Package Caches**

### 2. 설정
- Info.plist `LSApplicationQueriesSchemes`에 `spotify` 추가
- 로그인 scope에 `app-remote-control` 추가 (`SpotifyConfig.scopes`) → 기존 `needsRelogin` 흐름으로 준비 상태에 재로그인 안내가 뜸
- 연결 토큰: **기존 PKCE 액세스 토큰**을 연결 직전 `validAccessToken()`으로 받아 `connectionParameters.accessToken`에 넣음
- `authorizeAndPlayURI`는 **자동 호출 없음**. 개발자 메뉴 버튼 **[Spotify 앱으로 SDK 인증 (화면 전환)]**으로만 호출 (PKCE 토큰으로 연결이 안 될 때 대안). 이 버튼으로 받은 토큰은 메모리에만 두고, 있으면 그다음 연결부터 그 토큰을 씀

### 3. 새 파일 `LiveLyricsExperiment/SpotifyRemoteService.swift` (앱 타깃)
- 연결·끊김·연결 실패 관리, 연결되면 `playerState` 구독 (`subscribe(toPlayerState:)`)
- 델리게이트 메서드는 `nonisolated` + `Task { @MainActor in ... }` (SDK 객체는 꺼내 쓸 값만 먼저 뽑아서 넘김)
- 연결 시도 후 15초 동안 응답이 없으면 실패로 처리 (다음 시도가 막히지 않게)

### 4. 연결 시도 시점 (스위치 켜짐 + 추적 중일 때만, 이미 연결 중·연결됨이면 아무것도 안 함)
| 시점 | 코드 위치 | 빈도 제한 |
|---|---|---|
| 앱이 화면에 올 때 (처음 열기·복귀, 자동 시작 뒤) | `ContentView` `.task` / `scenePhase == .active` → `connectRemote("앱 화면")` | 없음 (이벤트성) |
| 단축어 실행 때 (새로 시작했을 때 + **이미 추적 중일 때도**) | `startFromShortcut()` | 없음 |
| ▶︎ 처리 때 (한도 차단 중이 아닐 때) | `resumeFromCard()` | 없음 |
| Web API가 재생 중을 확인했는데 SDK가 끊겨 있을 때 | `didUpdate()` → `remote.connect(..., throttled: true)` | **마지막 시도 후 60초 안이면 건너뜀** |
| 개발자 메뉴 [지금 연결 시도] · 스위치를 켤 때 | `RemoteExperimentSection` | 없음 |

### 5. 기록 (로그 `🛰` 줄, 카드·가사·폴링은 Web API 기준 그대로)
- `🛰 SDK 연결 시도 (이유) · 토큰: 기존 로그인 · 백그라운드 · 잠금`
- `🛰 SDK 연결됨` / `🛰 SDK 끊김 (이유) — 마지막 이벤트 후 N초` / `🛰 SDK 연결 실패 (이유)`
- `🛰 SDK 이벤트: 곡 변경 / 재생 / 일시정지 / 위치 이동 / 첫 상태 · ▶︎ 아티스트 - 제목 · 위치 M:SS · 앱 상태 · 잠금 여부`
- 비교: SDK가 알린 **곡 변경·재생·일시정지**를 Web API 조회가 같은 상태로 확인하면 `🛰 Web API보다 N.N초 빠름 (종류)`
  - Web API가 이미 같은 상태였으면 `🛰 Web API가 먼저 알아챔 (종류, N.N초 먼저)`
  - 2분 안에 Web API가 못 알아채면 `🛰 Web API가 2분 안에 같은 변화를 알아채지 못함`
  - 곡 비교는 SDK의 `spotify:track:ID`의 ID와 Web API의 곡 ID로 함
- 잠금 여부는 `isProtectedDataAvailable`(잠금 시 보호된 데이터 접근 불가)로 판단 → **잠근 직후 약 10초는 "잠금 해제"로 찍힐 수 있음**

### 6. 개발자 메뉴 "SDK 연결 실험" 구역
- **SDK 연결 실험** 스위치 (기본 꺼짐, 앱을 껐다 켜도 유지) · 연결 상태 · 마지막 이벤트 시각
- [지금 연결 시도] · [Spotify 앱으로 SDK 인증 (화면 전환)]
- 스위치를 끄거나 [정지]하면 SDK 연결을 끊음

## B. 카드 탭 → Spotify 열기
- Info.plist `CFBundleURLTypes`에 앱 주소 `livelyrics` 등록 (기존 로그인 콜백 `livelyrics://callback`은 로그인 창이 직접 받으므로 영향 없음)
- 잠금화면 카드 전체에 `.widgetURL(livelyrics://open-spotify)` — `LyricsLiveActivity.swift`의 잠금화면 뷰에만 (다이내믹 아일랜드는 그대로)
- ▶︎ 버튼은 그대로 `Button(intent:)` → 버튼 영역을 누르면 인텐트, 나머지 영역은 URL (iOS 규칙상 버튼이 우선)
- 앱이 주소를 받으면 (`ContentView.onOpenURL` → `ExperimentController.handleOpenURL`) 로그 `🔗 카드 탭 → Spotify 열기` 후 `spotify:`를 열어 Spotify 앱으로 전환. 열 수 없으면 `⚠️ Spotify 앱을 열 수 없어요` 로그만
- 카드 탭은 iOS 규칙상 **잠금 해제가 필요** (▶︎는 잠금 해제 없이 동작)

## 바꾼 파일과 이유
| 파일 | 바꾼 내용 | 이유 |
|---|---|---|
| `LiveLyricsExperiment.xcodeproj/project.pbxproj` | Swift 패키지 `SpotifyiOS` 추가 (앱 타깃) | A-1 |
| `LiveLyricsExperiment/SpotifyRemoteService.swift` (새 파일) | SDK 연결·구독·이벤트 기록·Web API 비교 | A-3·5 |
| `LiveLyricsExperiment/ExperimentController.swift` | `remote` 추가, 연결 시도 시점 연결, 정지 시 끊기, `handleOpenURL`·`openSpotify` | A-4, B-3 |
| `LiveLyricsExperiment/ContentView.swift` | 앱 화면 복귀 때 연결 시도, `onOpenURL`, 개발자 메뉴 "SDK 연결 실험" 구역 | A-4·6, B-3 |
| `Spotify/SpotifyConfig.swift` | scope `app-remote-control` | A-2 |
| `LiveLyricsExperiment/Info.plist` | `CFBundleURLTypes`(livelyrics), `LSApplicationQueriesSchemes`(spotify) | A-2, B-1 |
| `LyricsWidget/LyricsLiveActivity.swift` | 잠금화면 카드에 `widgetURL` | B-2 |
| `docs/dev/xcode-setup.md`, `docs/dev/progress.md` | 설정·진행 기록 | — |

## 빌드 결과
BuildProject **성공** (오류 0). 새 파일 `SpotifyRemoteService.swift`의 경고 0 (처음 빌드에서 나온 동시성 경고 2개는 고침). 남은 경고는 기존 `onChange(of:perform:)` 사용 중단 안내뿐 (기존 코드와 같은 방식).

## 지시서와 다르게 한 점과 이유
- **한도 차단 중에는 SDK 연결을 시도하지 않는다.** SDK 연결 자체는 Web API를 쓰지 않지만, 연결 직전 토큰 갱신이 Spotify 호출이라 008 규칙("차단 중 Spotify 호출 0")을 지키려고 막았다 → 아래 질문 1
- 단축어가 "이미 추적 중"일 때도 연결을 시도한다 (지시서의 "Spotify가 막 열렸을 때"를 살리려고)
- 위치 이동(seek) 이벤트는 기록만 하고 Web API와의 시간 비교는 하지 않는다 (지시서의 비교 대상 "같은 변화"를 곡 변경·재생·일시정지로 해석)

## 테스트 전 준비 (사용자)
1. **Spotify 개발자 대시보드** (developer.spotify.com → Dashboard → 이 앱 → **Settings** → **Edit**)
   - "Which API/SDKs are you planning to use?"에서 **iOS** 체크 (Web API는 그대로 체크)
   - **iOS app bundles**의 Bundle ID 칸에 `com.hwan.LiveLyricsExperiment` 입력 → **Save**
   - (이 등록이 없으면 SDK 연결이 거부될 수 있음. 기존 PKCE 토큰으로 연결할 때 꼭 필요한지는 실기기에서 확인)
2. Xcode에서 아이폰으로 실행 → 앱 준비 상태의 **재로그인** 안내대로 다시 로그인 (`app-remote-control` 권한)
3. 개발자 메뉴 → **SDK 연결 실험** 켜기

## 사용자가 아이폰에서 확인할 것 (최소)
준비: 위 1~3 → Spotify 재생 → 홈 화면 → 화면 잠금
1. **잠금 상태에서 즉시 반응하는지**: 잠금화면의 Spotify 컨트롤로 **다음 곡** 1번, **일시정지 → 재생** 1번 → 개발자 메뉴 로그에서 `🛰` 줄 확인 (연결 유지 여부, "Web API보다 N초 빠름")
2. **카드 탭**: 잠금화면 카드의 ▶︎가 아닌 부분 탭 → 잠금 해제 후 Spotify가 열리는지 (로그 `🔗 카드 탭 → Spotify 열기`)
- 로그는 `🛰`·`🔗` 줄만 복사해서 주면 됨
- 기존 토큰으로 `🛰 SDK 연결 실패`가 계속 나오면: 개발자 메뉴 [Spotify 앱으로 SDK 인증] 1번 → 다시 1번 테스트 (화면이 Spotify로 바뀌고 마지막 곡이 재생될 수 있음)

## 질문
1. 한도 차단 중 SDK 연결을 막아 두었는데, 차단 중에 SDK가 대체 수단이 될 수 있는지도 보려면 "토큰이 아직 유효할 때(갱신 불필요)만 연결" 같은 예외를 둘까요? (지금은 008 규칙 우선)
