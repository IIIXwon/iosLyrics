# Xcode / 외부 설정 (변경 시 주의)

설정을 바꾸라고 안내할 때는 클릭 경로까지 적을 것 (사용자는 iOS 초보).

## 앱 타깃 `LiveLyricsExperiment`
- **Background Modes**: ✅ Location updates, ✅ Audio·AirPlay·PiP
- **Info.plist**
  - `NSSupportsLiveActivities = YES`
  - `NSLocationWhenInUseUsageDescription`
  - `NSLocationAlwaysAndWhenInUseUsageDescription`
  - `NSLocationDefaultAccuracyReduced = YES`

## 두 타깃 공통
- **Minimum Deployments ≤ 실제 아이폰 iOS 버전** — 위젯 쪽이 더 높으면 Live Activity가 안 뜸
- 최소 iOS 16.4 이상 (`@Environment(\.webAuthenticationSession)` 사용)
- `LyricsActivityAttributes.swift`는 Target Membership 두 타깃 모두 체크

## Spotify 개발자 대시보드
- Redirect URI: `livelyrics://callback`
- API: Web API 선택
- 앱 소유자 계정 **Premium 필수**

## Apple 계정
- 무료 계정(Personal Team): 7일마다 재서명, 기기당 앱 3개
