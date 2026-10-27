# 011 — Spotify Client ID를 SpotifySecrets.swift로 분리

상태: 대기

> 작성: 리드 (Claude Code 메인 세션) · `qa`·`ios-dev`는 **읽기만**
> 작성일: 2026-10-27 · 근거: decisions 2026-10-27 "Client ID는 외부 노출 금지, 로컬에서만 사용", roadmap P0 "다음 작업 011 (시범 운행)"

## 목적
1. Client ID를 git에 올라가지 않는 파일 `Spotify/SpotifySecrets.swift`(이미 `.gitignore`에 있음)로 옮긴다
2. `Spotify/SpotifyConfig.swift`에는 실제 값이 남지 않게 해서, 지금처럼 매번 "수정됨(M)" 상태로 남아 커밋에서 빼야 하는 불편을 없앤다
3. 새 작업 구조(`/task` → `/judge`)의 첫 시범 운행

## 할 일

### A. 리드 (계약 파일) — ③ 전에 리드가 끝내 둔다
1. `LiveLyricsExperiment.xcodeproj/project.pbxproj`에 `Spotify/SpotifySecrets.swift`를 **앱 타깃 `LiveLyricsExperiment`에만** 추가 (Spotify 그룹 + Sources). 위젯 타깃에는 넣지 않는다
   - `Spotify/` 폴더는 자동 동기화 폴더가 아니라서 파일을 만들기만 하면 빌드에 포함되지 않는다

### B. `ios-dev`
1. **`Spotify/SpotifySecrets.swift` 만들기** (git에 올라가지 않음)
   ```swift
   // 앱 타깃 — 로컬 전용 비밀값. ⚠️ git에 올리지 말 것 (.gitignore에 있음)
   enum SpotifySecrets {
       static let clientID = "<지금 SpotifyConfig.swift에 있는 실제 값>"
   }
   ```
   - 실제 값은 현재 작업 폴더의 `Spotify/SpotifyConfig.swift`(로컬 수정본)에서 옮긴다
2. **`Spotify/SpotifyConfig.swift`**: `static let clientID = SpotifySecrets.clientID`로 바꾼다. 주석은 "Client ID는 `SpotifySecrets.swift`에 (예시: `SpotifySecrets.swift.example`)"로 고친다. `redirectURI`·`scopes`·`isConfigured`는 그대로
3. **`Spotify/SpotifySecrets.swift.example` 만들기** (git에 올라감, 빌드에 포함 안 됨 — 확장자가 `.example`이라 컴파일되지 않음)
   - 1번과 같은 모양, 값은 `"여기에 Client ID"` (→ `isConfigured`가 false가 되는 값)
   - 맨 위 주석: 이 파일을 복사해 `SpotifySecrets.swift`로 이름을 바꾸고 값을 넣으라는 안내
4. **`docs/dev/xcode-setup.md`**: Client ID 설정 방법을 "`SpotifySecrets.swift.example` 복사 → `SpotifySecrets.swift` → 값 입력"으로 갱신. 새로 받은 폴더에서 이 파일이 없으면 빌드가 "cannot find 'SpotifySecrets'"로 실패한다는 점도 적는다
5. 보고서 `docs/dev/reports/011-report.md` (상태: 검토 요청)

## Red 목록
없음 — 동작 변경 없이 값의 위치만 옮긴다 (빌드 성공 + 아이폰 로그인 유지로 확인)

## 새 함수 시그니처
없음

## 주의
- ⚠️ **실제 Client ID 값은 보고서·로그·답변에 절대 적지 않는다.** 확인이 필요하면 "32자리 값 옮김" 정도로만 쓴다
- Client ID가 그대로라서 키체인의 기존 토큰이 계속 유효해야 한다 (재로그인 불필요)
- 컴파일 확인은 CLAUDE.md "명령"의 빌드·테스트 명령으로

## 하지 말 것
- `.gitignore`, `project.pbxproj`, Info.plist, `LyricsActivityAttributes.swift`, `LiveLyricsTests/`, `docs/plan/`, `CLAUDE.md` 수정 금지
- `redirectURI`·`scopes`·로그인·토큰 저장 방식 변경 금지
- Info.plist·xcconfig·환경 변수 등 다른 비밀값 방식 도입 금지 (이번엔 Swift 파일 분리만)
- git 명령 금지 (리드가 함)

## 완료 조건
- 빌드 명령·테스트 명령 성공
- `git status`에 `Spotify/SpotifyConfig.swift`가 커밋 가능한 변경으로만 나타나고(실제 값 없음), `Spotify/SpotifySecrets.swift`는 나타나지 않음 (`git check-ignore`로 무시 확인)
- `git grep -E '[0-9a-fA-F]{32}' -- Spotify` 결과가 작업 폴더 기준 0 (SpotifySecrets.swift 제외)
- `scripts/check.sh` 전부 ✅

## 사용자가 아이폰에서 확인할 것
1. Xcode에서 실기기로 설치(▶︎) 후 앱을 열었을 때 **"준비 상태"의 Spotify 로그인이 ✅** (다시 로그인하라고 하지 않음)
2. Spotify에서 곡을 재생하면 앱의 현재 재생·잠금화면 카드 가사가 평소처럼 나옴
3. (선택) 개발자 메뉴 [전체 복사] 로그에 토큰 갱신·401 관련 ❌가 없음
