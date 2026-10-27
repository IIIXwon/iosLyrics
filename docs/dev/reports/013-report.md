# 013 보고서 — 잠금화면 카드 단순화 + 다이내믹 아일랜드 비우기

상태: 검토 요청

## 변경 파일
- `LyricsWidget/LyricsLiveActivity.swift`: 카드의 제목·가수 줄과 `PlaybackTimeRow` 삭제(구조체 포함), 아일랜드 compact·minimal을 `EmptyView()`로, 맨 위 주석 정리
- `LiveLyricsExperiment/ExperimentController.swift`: `updateReason`에서 "시간 보정"·"일시정지 중 위치 이동" 삭제, 파일 맨 위 주석 갱신
- `docs/dev/architecture.md`: 카드 구성·아일랜드·갱신 조건 갱신

## 검증
- 빌드(generic/platform=iOS): 오류 0
- 테스트(iPhone 18 Pro): 기존 테스트 통과 (실패 없음)
- `scripts/check.sh`: 모두 ✅
- `grep -n "PlaybackTimeRow\|trackInfo" LyricsWidget/*`: 결과 없음

## 피드백 처리
없음

## 남은 이슈·질문
- 지시서와 다른 점 1개: expanded 영역을 완전히 빼면 `DynamicIsland` 생성자가 제네릭 추론 실패로 컴파일되지 않음. 그래서 `DynamicIslandExpandedRegion(.center) { EmptyView() }` 빈 영역 하나만 남김(내용 없음). 화면 결과는 같을 것으로 보지만 아일랜드가 실제로 비는지는 실기기 확인 필요.
- `makeState`는 그대로 둠(`trackInfo` 등은 계약 필드라 계속 채워 보냄).

## 리뷰 반영

### 수용 (5건)
1. `updateReason`: `current`만 비교 → `linesChanged(old, new)`(previous·current·next 중 하나라도 다르면 "표시 내용 변경"). 근거: 시간 보정 갱신을 없애서, 반복 후렴 seek나 같은 줄이 연달아 나올 때 이전·다음 줄이 바뀌지 않는 문제를 막음.
2. `scheduleNextLine`: `current` 비교를 같은 `linesChanged` 기준으로 변경(`lastSent`가 없으면 갱신). 근거: 1번과 같은 기준을 써야 두 경로가 어긋나지 않음.
3. `syncOffset` didSet: `sendCard` 직접 호출 → `makeState` 후 `updateReason`을 거쳐 바뀐 게 있을 때만 갱신(로그 이유는 "<이유> (싱크 보정 +0.25초)"). 근거: 카드 갱신은 "바뀐 게 있을 때만"이라는 기존 경로 재사용.
4. `LyricsLiveActivity.swift`: `DynamicIsland`에 `.widgetURL(URL(string: "livelyrics://open-spotify"))` 추가. 근거: 잠금화면 카드와 동일한 탭 동작.
5. `ExperimentController.swift`의 낡은 주석 "(시계는 iOS가 알아서 흐름)" 삭제. 근거: 카드에 시간 표시가 없어짐.

### 리드 기각 (2건)
- `makeState`의 위젯 미사용 필드(`trackInfo` 등) 채우기: 계약 유지 결정(지시서 "주의")에 따라 그대로 둠.
- 빈 expanded 영역(`DynamicIslandExpandedRegion(.center) { EmptyView() }`)의 주석 요청: 빌드로 필요성이 확인되어 기각.

### 실기기 확인 1건
- 빈 아일랜드가 compact 자리를 차지해 Spotify 표시를 minimal로 밀어내는지.

### 검증
- 리드가 `** BUILD SUCCEEDED **` 확인. 반영 중 주석 삭제로 닫는 중괄호가 합쳐져 생긴 빌드 오류는 줄을 나눠 복구함.
