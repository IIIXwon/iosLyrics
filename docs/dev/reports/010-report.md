# 010 보고서 — SDK 제거 + 카드 탭 후 자동 재생 + 반복 로그 정리

상태: 검토 요청

> 작성: Xcode Agent (개발 담당) · 지시서: `docs/plan/tasks/010-remove-sdk-tap-autoplay.md`
> 작성일: 2026-10-27

## 한 줄 요약
A(SDK 완전 제거) · B(카드 탭 → Spotify 열기 → 자동 재생) · D(반복 로그 3종 제거) · C(문서)를 마쳤고 BuildProject가 성공했다. SDK 흔적과 지운 로그 3종은 검색 결과 0이다 (`💓 조회 재개`는 남음). **Xcode에서 사용자가 클릭할 단계는 없다.** 폴링 간격·한도 처리·`idleGrace`·카드 갱신 조건·백그라운드 유지·▶︎ 버튼 동작은 바꾸지 않았다.

## A. SDK 완전 제거
1. **Swift 패키지 제거**: 009에서 Agent가 `project.pbxproj`에 넣은 패키지 관련 27줄만 있었기 때문에, 이 파일을 **커밋 상태로 되돌렸다**. 패키지 참조와 앱 타깃 Frameworks 연결이 함께 빠졌다. 패키지 잠금 파일(`project.xcworkspace/xcshareddata/swiftpm/Package.resolved`)도 지웠다
   - 빌드 로그에 Xcode가 예전 `SpotifyiOS.framework`·`SpotifyRemoteService.o`를 지운 기록(`Removed stale file`)이 남아 있어서 실제로 빠진 것을 확인했다
   - 사용자 클릭 단계: 없음. (혹시 Xcode 왼쪽 목록에 **Package Dependencies**가 남아 보이면 Xcode를 껐다 켜면 사라짐)
2. `LiveLyricsExperiment/SpotifyRemoteService.swift` 삭제
3. 호출부 정리
   - `ContentView`: 앱 화면에 올 때 연결 시도, 개발자 메뉴 "SDK 연결 실험" 구역(스위치·상태·[지금 연결 시도]·[Spotify 앱으로 SDK 인증]) 삭제
   - `ExperimentController`: `remote` 프로퍼티, ▶︎·단축어(2곳)·`didUpdate`의 연결 시도와 Web API 비교 기록, 정지할 때 연결 끊기, `connectRemote`, 앱 주소의 `callback`(SDK 인증) 처리 삭제
4. `UserDefaults` 키 `sdkExperimentEnabled`: 앱이 시작될 때 지운다 (`ExperimentController.init`). 읽는 곳은 없다
5. `SpotifyConfig.scopes`에서 `app-remote-control` 제거
   - `needsRelogin`: 예전에는 "기록된 권한 문자열 == 지금 권한 문자열"로 판단해서, 권한이 **줄어도** 재로그인을 요구했다. 이제는 **지금 필요한 권한이 기록된 권한의 부분집합이면** 재로그인을 요구하지 않는다 (`SpotifyAuth.hasRequiredScopes`). 009 때 다시 로그인했다면 기록된 권한에 `app-remote-control`이 더 있을 뿐이라 그대로 통과한다
6. **유지**: Info.plist `CFBundleURLTypes`(livelyrics), `LSApplicationQueriesSchemes`(spotify)
7. 검색 결과 (앱 코드·위젯·프로젝트 파일)
   - `SpotifyiOS` 0 · `SPTAppRemote` 0 · `🛰` 0 · `SpotifyRemote` 0 · `app-remote-control` 0
   - `sdkExperimentEnabled`는 위 4번의 "지우기" 한 줄만 남음

## B. 카드 탭 → Spotify 열기 → 자동 재생 (`ExperimentController`)
흐름 (`openSpotify()` → `startSpotifyWait()` → `waitForSpotifyDeviceAndPlay()`):
1. 카드 탭 → `🔗 카드 탭 → Spotify 열기` → `spotify:` 열기
2. 추적 중이고 **한도 차단 중이 아니면** 대기 시작: `🔗 Spotify 열림 → 연결 대기 (최대 20초)`
   - 이미 대기 중이면 새로 만들지 않음: `🔗 이미 연결 대기 중 — 이어서 기다려요` (다시 카드 탭)
3. 2초마다 최대 10번(20초):
   - 폴링이 이미 재생 중을 확인했으면 → `🔗 이미 재생 중 → 대기 종료` (재생 요청 안 함)
   - 기기 목록(`GET /me/player/devices`)에서 **기억한 기기, 없으면 `Smartphone` 기기**를 찾음 (기존 404 대응과 같은 기준)
   - 찾은 기기가 **활성 기기**면 재생 상태를 1번 조회해서, 재생 중이면 → `🔗 이미 재생 중 → 대기 종료` (아래 "다르게 한 점" 2)
   - ▶︎의 재생 요청이 진행 중이면 겹쳐 보내지 않고 종료 (`playRequestInProgress` 공유)
   - 아니면 `🔗 기기 나타남 (N초) → 재생 요청` → 그 기기로 재생 요청 1번 (`playOnce(device:)`, 404면 기존 순서대로 재생 이전 1회까지)
   - 재생 요청 뒤: 위치 추적이 꺼져 있으면 켬 → 폴링 재개 → 1초 뒤 즉시 1회 조회 → 카드·가사 갱신 (▶︎ 흐름과 같은 순서·같은 함수)
4. 20초 안에 기기가 없으면 `🔗 20초 동안 기기 없음 → 대기 종료`
5. 대기 중 한도 차단을 받으면 기존 한도 차단 처리(`handleQuotaBlock`)로 넘기고 종료. [정지]를 누르면 대기도 취소
- 호출 수: 대기 1번당 기기 목록 최대 10회 + 재생 1회 (+ 활성 기기일 때 재생 상태 조회 1회). 모두 008 호출 수 기록에 포함됨 (`SpotifyAPI`를 그대로 씀)
- `playOnce`는 `device` 인자만 추가했고, 주지 않으면(▶︎ 버튼) 예전과 똑같이 기억한 기기로 요청한다

## D. 반복 로그 제거
| 로그 | 처리 |
|---|---|
| `💓 조회 #N · …` (10회마다) | 호출 삭제 (`didUpdate`) |
| `🪪 카드 갱신 #N — 가사 줄 변경` | 이유가 "가사 줄 변경"일 때만 기록 안 함 (`sendCard`). 갱신 횟수는 계속 세서 `⏹ 정지` 요약에 들어감 |
| `📍 위치 수신 #N` | 호출 삭제 (`LocationKeepAlive.received()`). 받은 횟수는 계속 셈 (재시작 확인 로그·정지 로그에서 씀) |
- 남긴 것: `💓 조회 재개`, `⏹ 정지` 요약, 나머지 `🪪 카드 갱신` 이유들, 그 밖의 로그 전부. 판단이 애매해서 지운 로그는 없음

## C. 문서 (`docs/dev/`)
- `architecture.md`: SDK 제거 사실, 카드를 누르는 곳(▶︎ / 나머지 영역) 흐름 추가. 예전 그대로 남아 있던 "1초 폴링"을 008 기준(3초·15초·10초)으로 고침
- `xcode-setup.md`: SDK 패키지·scope·대시보드 iOS 등록 내용 제거 (Info.plist 두 항목은 카드 탭 용도로 남김)
- `progress.md`: 009 결론, 010 반영

## 바꾼 파일과 이유
| 파일 | 바꾼 내용 | 이유 |
|---|---|---|
| `LiveLyricsExperiment.xcodeproj/project.pbxproj` | 커밋 상태로 되돌림 (SDK 패키지 제거) | A-1 |
| `…/xcshareddata/swiftpm/Package.resolved` | 삭제 | A-1 |
| `LiveLyricsExperiment/SpotifyRemoteService.swift` | 삭제 | A-2 |
| `LiveLyricsExperiment/ContentView.swift` | SDK 연결 시도·개발자 메뉴 구역 삭제 | A-3 |
| `LiveLyricsExperiment/ExperimentController.swift` | SDK 호출부 삭제, 실험 스위치 키 지우기, 카드 탭 후 대기·자동 재생, `playOnce(device:)`, 로그 2종 정리 | A-3·4, B, D |
| `LiveLyricsExperiment/LocationKeepAlive.swift` | `📍 위치 수신` 로그 삭제 | D |
| `Spotify/SpotifyConfig.swift` | `app-remote-control` 제거 | A-5 |
| `Spotify/SpotifyAuth.swift` | `needsRelogin`을 부분집합 판단으로 | A-5 |
| `docs/dev/architecture.md`, `xcode-setup.md`, `progress.md` | 위 C | C |

## 빌드 결과
BuildProject **성공** (오류 0). 이번에 바꾼 코드에서 새 경고 없음. 남은 경고는 원래 있던 것뿐 (`onChange(of:perform:)` 사용 중단 안내, `LocationKeepAlive.swift`의 기존 동시성 경고 1개).

## 지시서와 다르게 한 점과 이유
1. **위치 추적을 재생 요청 뒤가 아니라 카드를 탭한 순간(앱이 화면에 있을 때) 켠다.** 4분 넘게 멈춰 있었다면 위치 추적이 꺼져 있다. 그 상태로 Spotify로 넘어가면 우리 앱은 곧 일시 중단돼서, 20초 대기 자체가 돌지 못한다. 그래서 화면에 있는 탭 시점에 켜고(백그라운드보다 확실히 켜짐), 재생 요청 뒤에는 꺼져 있을 때만 다시 켠다. 기기가 끝내 안 나타나 재생이 안 되면, 기존 규칙대로 3분 뒤 위치 추적이 꺼진다
2. **"기기 목록의 활성 기기 = 이미 재생 중"으로 바로 치지 않고, 재생 상태를 1번 조회해서 확인한다.** 활성 기기여도 일시정지일 수 있다. 그대로 대기를 끝내면 이번 작업의 목적(재생을 안 눌러도 이어짐)이 안 될 수 있어서다. 활성 기기일 때만 조회 1회가 더 든다

## 사용자가 할 것
- (선택) Spotify 개발자 대시보드 → 앱 → **Settings** → **Edit** → **iOS app bundles**에서 `com.hwan.LiveLyricsExperiment` 삭제 → **Save**. 그대로 둬도 동작에는 영향 없음
- 재로그인은 필요 없음 (준비 상태에 재로그인 안내가 뜨면 그것도 알려 주기 — A-5가 잘못된 것)

## 사용자가 아이폰에서 확인할 것 (1개)
- 오래(4분 이상) 멈춤 → 잠금화면 카드의 **▶︎가 아닌 부분** 탭 → 잠금 해제 → Spotify가 열린 뒤 **아무것도 누르지 않고** 기다리기 → 음악과 가사가 이어지는지
- 안 되면 `🔗` 줄과 그 근처의 `📍`·`⚠️`·`▶︎` 줄을 복사해서 주기

## 질문
- 없음
