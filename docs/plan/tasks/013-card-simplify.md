# 013 — 잠금화면 카드 단순화 + 다이내믹 아일랜드 비우기

상태: 완료

> 작성: 리드 (Claude Code 메인 세션) · `qa`·`ios-dev`는 **읽기만**
> 작성일: 2026-10-27 · 근거: 사용자 요청 (카드는 가사만, 다이내믹 아일랜드 자리 차지하지 않기)

## 목적
1. 잠금화면 카드 맨 위 **"제목 · 가수" 줄 제거**
2. 카드 아래 **재생 시간·진행 막대(`PlaybackTimeRow`) 제거**
3. Live Activity가 **다이내믹 아일랜드 영역을 차지하지 않게** 하기

⚠️ 3번 한계: iOS에는 Live Activity를 다이내믹 아일랜드에서 빼는 공식 설정이 없다. 최선은 아일랜드용 화면(compact·minimal·expanded)을 **전부 빈 화면(`EmptyView`)** 으로 두는 것. 실제로 아일랜드가 비는지는 아이폰에서 확인한다.

## 할 일 (`ios-dev`)
1. **`LyricsWidget/LyricsLiveActivity.swift`**
   - `LockScreenLyricsView`: `trackInfo` 줄과 `PlaybackTimeRow(state:)` 삭제. 이전·현재·다음 줄, 일시정지 때 "▶︎ 가사 다시 켜기" 버튼은 그대로
   - `PlaybackTimeRow` 구조체 삭제 (다른 곳에서 쓰지 않음)
   - `dynamicIsland:` 블록: expanded 영역을 모두 빼고, `compactLeading`·`compactTrailing`·`minimal`을 `EmptyView()`로. 왜 비워 두는지 한 줄 주석
   - 파일 맨 위 주석의 "재생 시간과 진행 막대가 스스로 흘러감" 문구 정리
2. **`LiveLyricsExperiment/ExperimentController.swift`** — 보이지 않는 변화로 카드를 갱신하지 않게
   - `updateReason`에서 `"시간 보정"`(trackStart 차이 0.7초 초과)·`"일시정지 중 위치 이동"` 조건 삭제. 나머지 조건(처음·곡 변경·표시 내용 변경·재생/일시정지)은 그대로
   - 가사 줄 계산은 앱 안에서 위치로 하므로 영향 없음. `makeState`는 그대로 둬도 됨
3. **`docs/dev/architecture.md`**: 카드 구성·갱신 조건 설명 갱신
4. 보고서 `docs/dev/reports/013-report.md` (상태: 검토 요청)

## Red 목록
없음 (화면 모양과 private 갱신 조건만 바뀜)

## 새 함수 시그니처
없음

## 주의
- 계약 `LyricsActivityAttributes.swift`는 **바꾸지 않는다**. `trackInfo`·`trackStart`·`trackEnd`·`pausedPosition`·`duration`은 위젯에서 안 쓰게 되지만 남겨 둔다 (기존 카드 이어받기(006)와 형식을 맞추기 위해)
- 최소 iOS 16.4에서 컴파일되는 API만 사용

## 하지 말 것
- 매초 카드 갱신 추가
- 아일랜드를 피하려고 카드를 끝내거나 다시 시작하기
- Info.plist·`*.xcodeproj` 수정
- 가사를 못 찾았을 때의 "아티스트 / 제목 / 앨범" 3줄 표시 변경 (이번 범위 아님)

## 완료 조건
- 빌드 성공, 기존 단위 테스트 통과
- `grep -n "PlaybackTimeRow\|trackInfo" LyricsWidget/` 결과 없음
- `scripts/check.sh` 통과

## 사용자가 아이폰에서 확인할 것
1. 잠금화면 카드: 제목·가수 줄과 시간·진행 막대가 없고 가사(이전·현재·다음 줄)만 보이는지
2. 일시정지 → "▶︎ 가사 다시 켜기" 버튼이 나오고, 눌러서 재개되는지
3. 홈 화면에서 Spotify 재생 중: 다이내믹 아일랜드에 우리 앱 표시가 없는지 (빈 알약이 남는지, Spotify 표시가 밀려나는지도 기록)
4. 잠근 상태로 몇 분 동안 가사 줄이 계속 바뀌는지

## 검토 1차 — 완료 (2026-10-27)
판정 근거: 사용자 아이폰 확인 "테스트 통과" (로그 첨부 없음 → qa 로그 모드 생략)
| 확인 항목 | 판정 |
|---|---|
| 1. 카드에 가사 줄만 (제목·시간·진행 막대 없음) | 통과 (사용자 확인) |
| 2. 일시정지 → "▶︎ 가사 다시 켜기" 재개 | 통과 (사용자 확인) |
| 3. 다이내믹 아일랜드에 우리 표시 없음 | 통과 (사용자 확인) |
| 4. 잠금 상태에서 가사 줄 계속 변경 | 통과 (사용자 확인) |

- 리드 확인: 빌드 성공, 단위 테스트 `** TEST SUCCEEDED **`, `scripts/check.sh` ✅
- `/code-review` 지적 8건: 반영 5 (세 줄 비교, 다음 줄 예약 같은 기준, 싱크 보정 갱신 조건, 아일랜드 탭 URL, 낡은 주석) / 기각 2 (위젯 미사용 필드 생성 — 계약 유지, 빈 expanded 주석 — 빌드로 확인) / 실기기 확인 1 (위 3번)

