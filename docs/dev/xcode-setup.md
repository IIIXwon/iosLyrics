# Xcode / 외부 설정 (변경 시 주의)

설정을 바꾸라고 안내할 때는 클릭 경로까지 적을 것 (사용자는 iOS 초보).

## 앱 타깃 `LiveLyricsExperiment`
- **Background Modes**: ✅ Location updates, ✅ Audio·AirPlay·PiP
- **Info.plist**
  - `NSSupportsLiveActivities = YES`
  - `NSLocationWhenInUseUsageDescription`
  - `NSLocationAlwaysAndWhenInUseUsageDescription`
  - `NSLocationDefaultAccuracyReduced = YES`
  - `CFBundleURLTypes`: 앱 주소 `livelyrics://` (카드 탭 `open-spotify`) — 작업 009
  - `LSApplicationQueriesSchemes`: `spotify` (카드 탭으로 Spotify 앱 열기) — 작업 009
- Swift 패키지 없음 (009의 `SpotifyiOS`는 010에서 제거)

## 두 타깃 공통
- **Minimum Deployments ≤ 실제 아이폰 iOS 버전** — 위젯 쪽이 더 높으면 Live Activity가 안 뜸
- 최소 iOS 16.4 이상 (`@Environment(\.webAuthenticationSession)` 사용)
- `LyricsActivityAttributes.swift`는 Target Membership 두 타깃 모두 체크

## Spotify 개발자 대시보드
- Redirect URI: `livelyrics://callback`
- API: Web API 선택 (009 때 넣은 iOS app bundles의 Bundle ID는 SDK 전용이라 지워도 됨)
- 앱 소유자 계정 **Premium 필수**

## Client ID 설정 (`SpotifySecrets.swift`)
Client ID는 git에 올라가지 않는 `Spotify/SpotifySecrets.swift`에 둔다 (`.gitignore`에 등록됨). 앱 타깃에만 포함, 위젯 타깃에는 넣지 않는다.
1. `Spotify/SpotifySecrets.swift.example`을 복사해 `Spotify/SpotifySecrets.swift`로 이름을 바꾼다
2. 파일 안의 `"여기에 Client ID"`를 대시보드(내 앱 → Settings)의 Client ID로 바꾼다
3. `SpotifyConfig.clientID`가 이 값을 읽는다. 값이 `"여기에"`를 포함하면 `isConfigured`가 false
- ⚠️ 새로 받은 폴더에서 이 파일이 없으면 빌드가 `cannot find 'SpotifySecrets' in scope`로 실패한다 → 위 1~2번을 먼저 한다
- `.example`은 확장자 때문에 컴파일되지 않는다. 실제 값을 넣지 말 것

## Apple 계정
- 무료 계정(Personal Team): 7일마다 재서명, 기기당 앱 3개
