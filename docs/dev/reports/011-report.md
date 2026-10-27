# 011 보고서 — Client ID를 SpotifySecrets.swift로 분리

상태: 검토 요청

## 변경 파일
- `Spotify/SpotifyConfig.swift` — `clientID = SpotifySecrets.clientID`로 변경, 주석 갱신 (실제 값 없음)
- `Spotify/SpotifySecrets.swift.example` — 새로 만듦 (값 `"여기에 Client ID"`)
- `docs/dev/xcode-setup.md` — "Client ID 설정" 절 추가 (파일이 없을 때 `cannot find 'SpotifySecrets'` 오류 안내 포함)
- `Spotify/SpotifySecrets.swift` — ios-dev는 권한 규칙 때문에 만들지 못했고, 사용자가 `.example`을 복사해 직접 만들어 Client ID를 넣음 (git 무시 대상, Claude는 읽지 않음)

## 검증 (리드가 직접 실행)
- 빌드: 성공 (BUILD_EXIT=0, 기존 onChange deprecated 경고만)
- 테스트: 'iPhone 18 Pro' 시뮬레이터에서 통과 (TEST_EXIT=0). 'iPhone 18'은 없는 기기
- `git check-ignore Spotify/SpotifySecrets.swift`: 무시됨
- 변경 파일·추적 파일에 32자리 값 0건

## 남은 이슈·질문
해소됨. SpotifySecrets.swift는 사용자가 직접 만들었고 검증도 끝남.

## 사용자가 테스트할 항목 (아이폰)
1. Xcode에서 실기기로 설치(▶︎) 후 앱을 열었을 때 "준비 상태"의 Spotify 로그인이 ✅ (다시 로그인하라고 하지 않음)
2. Spotify에서 곡을 재생하면 앱의 현재 재생·잠금화면 카드 가사가 평소처럼 나옴
3. (선택) 개발자 메뉴 [전체 복사] 로그에 토큰 갱신·401 관련 ❌가 없음
