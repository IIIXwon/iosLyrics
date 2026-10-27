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
