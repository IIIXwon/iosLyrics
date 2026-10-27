# 008 보고서 — Spotify 호출 줄이기 + 호출 한도 처리

상태: 검토 요청

> 작성: Xcode Agent (개발 담당) · 지시서: `docs/plan/tasks/008-api-quota.md`
> 작성일: 2026-10-26

## 한 줄 요약
지시서의 할 일 3가지(상황별 조회 간격 / 429 처리 / 하루 호출 수 기록)를 모두 구현했고 BuildProject가 성공했다. **아이폰에서는 확인하지 못했다** (지시서대로 계정이 차단 중이라 지금은 테스트 불가). Claude 앱이 코드로 확인할 항목은 아래 "코드 확인 위치"에 정리했다. 백그라운드 유지 방식·`idleGrace`·카드 갱신 조건은 바꾸지 않았다.

## 1. 상황별 조회 간격 (`NowPlayingService`)
| 상황 | 간격 | 코드 |
|---|---|---|
| 재생 중 | **3초** (기본값 1초 → 3초) | `interval = 3`, `nextInterval()` |
| 일시정지 중 (일시정지 유지 기간 포함) | **15초** | `pausedInterval` |
| 재생 중인 곡 없음 (유지 기간 아님) | **10초** | `noTrackInterval` |
| 곡이 끝날 때 | 끝나는 시점에 바로 1회 (기존 그대로) | `loop()`의 "곧 끝나면" 분기 |
| ▶︎·단축어·앱 열기·자동 시작 직후 | 즉시 1회 (기존 그대로) | `refreshNow()` |
- 조회 오류 후 대기(`interval × 3`)는 그대로. 가사 줄 예약(`lineTask`)은 앱이 계산하므로 영향 없음
- 개발자 메뉴 조회 간격: 이름을 "재생 중 조회 간격"으로 바꾸고 선택지를 **2·3·5초**로 (1초 제거)
- 일시정지 중 15초 간격이라, 사용자가 Spotify에서 직접 다시 재생하면 카드가 따라오기까지 최대 15초가 걸린다 (▶︎·앱 열기는 즉시 1회 조회)
- 조회 사이 공백으로 "앱이 중단됐었는지" 판단하는 `💓 조회 재개` 로그의 기준을 20초 → 40초로 올렸다 (일시정지 중 정상 간격이 15초라서)

## 2. 호출 한도(429) 처리
- **`Retry-After` 60초 이하**: 지금처럼 그만큼 기다렸다 재개 (`SpotifyAPIError.rateLimited(retryAfter:body:)`), 로그에 429 응답 본문도 붙인다
- **60초 초과 → 한도 차단** (`SpotifyAPIError.blocked(until:body:)`)
  - 재개 시각(지금 + Retry-After)을 `UserDefaults`(`spotifyBlockedUntil`)에 저장 → 앱을 껐다 켜도 유지 (`SpotifyBlock`, `SpotifyQuota.swift`)
  - **그 시각까지 Spotify Web API 호출 전부 중단**: `SpotifyAPI.get`/`put`이 요청을 만들기 **전에** 차단 여부를 확인(`ensureNotBlocked`)해서, 폴링·▶︎ 재생 요청·즉시 조회·기기 목록 모두 네트워크 요청 없이 바로 `blocked` 오류가 된다. 토큰 갱신도 이 확인 뒤에 일어나므로 차단 중에는 일어나지 않는다
  - 폴링 루프는 `blocked`를 받으면 스스로 멈추고(`task = nil`) 컨트롤러에 알린다
  - **카드**: 마지막 곡을 일시정지로 표시하고 안내 **"Spotify 조회 한도 초과 · 오전 10:11 이후 재개"** (재개 시각이 오늘이 아니면 날짜도 표시). 어떤 경로로 카드를 갱신해도 안내가 유지되도록 `makeState`가 마지막에 안내를 덮어쓴다 (`applyQuotaNotice`), 가사 줄 예약도 차단 중에는 만들지 않는다
  - **위치 추적 끄기**: 카드 갱신이 끝난 뒤에 끈다 (`🔋 한도 차단 중이라 위치 추적을 껐어요`)
  - **차단 중 ▶︎**: API 호출 없이 카드 안내만 다시 표시. 로그 `⛔️ 한도 차단 중 — 오전 10:11 이후 재개`. 앱이 새로 시작돼 안내 상태가 없어도 같은 처리로 안내를 다시 세운다
  - **재개**: 재개 시각이 지난 뒤 앱 열기(`autoStartIfNeeded`)·▶︎·단축어 때 `resumeAfterQuotaBlockIfExpired()`가 저장된 시각을 지우고 안내를 걷은 뒤 위치 추적·폴링을 다시 시작한다 (`✅ 한도 차단이 풀렸어요`)
  - 차단 중 단축어: 새 카드를 만들지 않고 `⛔️ 한도 차단 중 — … 이후 재개` 로그만 남긴다 (어차피 조회를 못 하므로)
  - 앱이 종료됐다가 차단 중에 다시 시작되면: 남은 카드를 이어받은 뒤 첫 조회가 `blocked`로 끝나 같은 안내가 세워진다
- **준비 상태**에 항목 **"Spotify 조회"** 추가: 차단 중이면 ❌ `호출 한도 초과 · 오전 10:11 이후 재개`(버튼 없음), 아니면 ✅ "정상". ❌가 있으므로 자동 시작도 하지 않는다
- 429 응답 본문(`reason` 등)을 로그에 남긴다 (`⛔️ 응답: …`)

## 3. 하루 호출 수 기록
- 실제로 요청을 보내기 직전에 **날짜별·종류별**로 센다 (`APIUsage`, `UserDefaults` `spotifyAPICallCounts`, 최근 7일만 유지)
  - 종류: 재생 상태 조회(`/me/player`) / 재생 요청(play·재생 기기 이전) / 기기 목록 / 토큰 갱신(토큰 엔드포인트 호출 전부)
  - 401 때문에 토큰을 갱신하고 같은 요청을 다시 보내면 요청 2번으로 센다. 차단돼서 보내지 않은 요청은 세지 않는다. LRCLIB은 세지 않는다
- **개발자 메뉴**에 "Spotify 호출 수" 구역: 오늘·어제 합계와 종류별 횟수, 차단 중이면 재개 시각
- 429를 받으면 로그: `⛔️ 한도 초과 — 오늘 호출 N회째 (재생 상태 조회 M · 재생 요청 … · 기기 목록 … · 토큰 갱신 …)`

## 코드 확인 위치 (Claude 앱 검토용)
| 확인 항목 | 위치 |
|---|---|
| 상황별 간격 | `NowPlayingService.nextInterval()` · `loop()` |
| 429 60초 기준 분기 | `SpotifyAPI.rateLimitError(_:_:)` (`after > 60`이면 `SpotifyBlock.set` + `.blocked`) |
| 차단 중 API 호출 0 | `SpotifyAPI.ensureNotBlocked()` — `get`·`put` 첫 줄 (`auth.validAccessToken()`보다 앞) |
| 재개 시각 저장·복원 | `SpotifyBlock` (`UserDefaults`), 만료 시 `until` getter가 지움, 재개 `ExperimentController.resumeAfterQuotaBlockIfExpired()` |
| 카드 안내 순서 | `ExperimentController.handleQuotaBlock` — `sendCard` 먼저, 끝난 뒤 `location.stop()` |
| 호출 수 기록 | `APIUsage.record` (`SpotifyAPI.get`/`put`, `SpotifyAuth.requestToken`) |

## 바꾼 파일과 이유
| 파일 | 바꾼 내용 | 이유 |
|---|---|---|
| `SpotifyQuota.swift` (새 파일, 앱 타깃) | `APIUsage`(호출 수), `SpotifyBlock`(차단 재개 시각) | 할 일 2·3 |
| `Spotify/SpotifyAPI.swift` | 429 분기·`blocked` 오류·차단 사전 확인, 호출 수 기록 | 할 일 2·3 |
| `Spotify/SpotifyAuth.swift` | 토큰 호출 수 기록 | 할 일 3 |
| `Spotify/NowPlayingService.swift` | 상황별 간격, 한도 차단 처리(`onBlocked`, 루프 중단), 429 대기 로그 | 할 일 1·2 |
| `ExperimentController.swift` | 한도 차단 처리·재개, 카드 안내 덮어쓰기, ▶︎·단축어·앱 열기 때 확인 | 할 일 2 |
| `ReadinessModel.swift` | "Spotify 조회" 항목 | 할 일 2 |
| `ContentView.swift` | 개발자 메뉴: 호출 수 구역, 조회 간격 이름·선택지 | 할 일 1·3 |

## 빌드 결과
BuildProject **성공** (오류 없음). 호출 수 기록(오늘 합계·종류별 요약)과 차단 시각 저장·만료는 코드 조각으로 직접 실행해 동작을 확인했다.

## 지시서와 다르게 한 점과 이유
- 없음.

## 사용자가 아이폰에서 확인할 것 (최소)
⚠️ 지금 계정은 **2026-10-27 오전 10시쯤까지 차단** 상태 → 그 전에는 테스트 불가
1. 차단이 풀린 뒤 **하루 평소처럼 사용** → 다음 날 개발자 메뉴의 **어제 호출 수**만 알려 주기 (한도 초과가 없었는지 함께)
- 참고: 차단이 풀리기 전에 앱을 열면 준비 상태의 "Spotify 조회"가 ❌로 보이는 것으로 차단 처리 동작을 미리 볼 수 있다

## 질문
- 없음
