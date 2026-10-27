# 012 보고서 — 가사 서버 일시 오류 대응

상태: 검토 요청

## 변경 파일
- `LiveLyricsExperiment/LyricsService.swift`: `LyricsRetryPolicy`(isTransient, delay(afterFailure:)) 추가
- `LiveLyricsExperiment/ExperimentController.swift`: `searchWithRetry`가 규칙 사용 (일시 오류만 2·5·15·30·60초, 비일시 오류는 즉시 중단, 곡 변경·취소 시 즉시 중단 유지)
- `docs/dev/architecture.md`: 재시도 설명 갱신

## 검증
- 빌드(generic/platform=iOS): 성공 (기존 deprecated 경고만)
- 테스트(iPhone 18 Pro): LyricsRetryPolicyTests 10개 전부 통과
- `scripts/check.sh`: 모두 ✅

## 남은 이슈·질문
없음. 카드 갱신 흐름(`sendCard`)은 변경 없음 (끝내 실패 시 `가사 없음`, 성공 시 `가사 도착`).
