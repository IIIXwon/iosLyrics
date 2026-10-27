# 003 — SideStore 설치용 .ipa 만들기

상태: 하지 않음 (2026-10-27 사용자 결정. 2026-10-26부터 보류 — 매주 Xcode로 다시 설치)

> 작성: Claude 앱 (계획 담당) · Xcode Agent는 **읽기만**
> 작성일: 2026-10-26

## 목적
Xcode 직접 설치는 7일마다 만료된다. 일상용은 **SideStore**(별도 Apple ID)로 설치해 자동 재서명하고, Xcode는 개발용으로 계속 쓴다.
이번 작업은 SideStore에 넣을 **.ipa 파일을 만드는 방법을 확정하고 실제로 하나 만드는 것**이다. 기능 변경은 없다.

## 할 일
1. **.ipa 만드는 방법 확정**
   - 1안: Xcode **Product → Archive** (Release) → Organizer에서 내보내기. 무료 계정(Personal Team)에서 내보내기가 막히면 2안
   - 2안: Archive 결과(`.xcarchive/Products/Applications/LiveLyricsExperiment.app`)를 `Payload/` 폴더에 넣고 zip으로 묶어 확장자를 `.ipa`로 (SideStore가 다시 서명하므로 서명 상태는 상관없음)
   - Agent가 직접 실행할 수 없는 단계는 **사용자가 Xcode 메뉴에서 할 순서**를 클릭 경로까지 적는다
2. **.ipa 안에 위젯 확장이 들어 있는지 확인**: `LiveLyricsExperiment.app/PlugIns/` 안에 위젯 `.appex`가 있어야 함 (없으면 잠금화면 카드가 안 뜸)
3. **번들 ID가 바뀌어도 괜찮은지 점검** (SideStore는 설치할 때 번들 ID 뒤에 팀 ID 등을 붙일 수 있음)
   - 코드·설정에 번들 ID를 직접 적어 둔 곳이 있는지 (키체인, UserDefaults, 파일 경로, Live Activity, 인텐트 등)
   - 앱과 위젯 사이에 공유 데이터(App Group)를 쓰는지 → 쓴다면 SideStore 설치본에서 깨질 수 있으니 보고
   - Spotify Redirect URI(`livelyrics://callback`)는 번들 ID와 무관한지 확인
4. **버전 번호**: 다음 설치 때 덮어쓰기가 되도록 빌드 번호(`CURRENT_PROJECT_VERSION`)를 올리는 규칙을 정해 문서화
5. **개발 쪽 문서** `docs/dev/sideload.md` 작성: .ipa 만드는 순서, 주의점, 업데이트할 때 순서

## 하지 말 것
- 앱 기능 코드 변경 금지 (점검 결과 수정이 필요하면 보고서 "질문"에 남기고 멈출 것)
- App Group·푸시 등 무료 계정에서 안 되는 기능 추가 금지
- `docs/plan/`, `CLAUDE.md` 수정 금지

## 완료 조건
- BuildProject 성공
- `.ipa` 파일 1개 생성 (위치를 보고서에 기록) — Agent가 못 만들면 사용자 안내 순서로 대체
- `docs/dev/sideload.md`, `docs/dev/reports/003-report.md` 작성 (상태: 검토 요청)

## 사용자가 할 것 (Agent 작업과 별개, Claude 앱이 안내함)
1. SideStore용 새 Apple ID 만들기
2. 아이폰에 SideStore 설치 (iloader + LocalDevVPN) — **LiveContainer 말고 SideStore만**
3. 003 완료 후: Xcode 설치본 삭제 → SideStore로 .ipa 설치 → Spotify 재로그인·위치 권한·실시간 현황 허용
4. 확인: 잠금화면 가사, 카드 ▶︎, SideStore "새로 고침"이 되는지 (7일 자동 갱신은 일주일 뒤 확인)
