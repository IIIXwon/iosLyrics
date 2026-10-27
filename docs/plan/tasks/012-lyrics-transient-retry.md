# 012 — 가사 서버 일시 오류 대응 (같은 곡 재생 중 다시 시도)

상태: 대기

> 작성: 리드 (Claude Code 메인 세션) · `qa`·`ios-dev`는 **읽기만**
> 작성일: 2026-10-27 · 근거: 011 검토 1차 범위 밖 관찰 (LRCLIB HTTP 503), roadmap P3

## 목적
LRCLIB이 잠깐 503 등을 돌려주면 지금은 3번(즉시·2초·5초) 시도 후 그 곡이 끝날 때까지 "가사 없음"으로 남는다
(011 로그: Espresso 9:12:23 실패 → 12초 뒤 다시 재생했을 때 성공).
1. **일시 오류**(서버 5xx·429·네트워크 끊김/시간 초과)면 같은 곡을 재생하는 동안 **간격을 늘려 더 시도**한다
2. **일시 오류가 아닌 오류**(400 같은 요청 오류, 취소)는 **바로 멈춘다** (지금은 모든 오류를 재시도함)

참고: 끝내 실패해도 검색 기록(`search-log.json`)은 남기지 않는 현재 동작은 그대로 → 다음 재생 때 다시 검색 (24시간 대기에 걸리지 않음, 확인됨 `ExperimentController.swift:750-757`)

## 할 일 (`ios-dev`)
1. **`LiveLyricsExperiment/LyricsService.swift`에 재시도 규칙 추가** (순수 로직, 아래 시그니처)
   - `isTransient`: `LyricsError.http(code)`는 `code >= 500` 또는 `code == 429`면 true, 그 외 false. `URLError`는 `.cancelled`만 false, 나머지 true. 그 밖의 오류는 false
   - `delay(afterFailure:)`: n번째 실패 뒤 기다릴 초. 1→2, 2→5, 3→15, 4→30, 5→60, 6 이상→nil(그만). 0 이하→nil
     → 최대 6번 시도, 첫 시도부터 마지막 시도까지 약 2분
2. **`ExperimentController.searchWithRetry`가 위 규칙을 사용**
   - 실패하면 `isTransient`가 false → 바로 nil (로그 `⚠️ 가사 조회 실패 (재시도 안 함): …`)
   - true → `delay(afterFailure: n)`만큼 기다렸다 재시도, nil이면 끝 (로그 `⚠️ 가사 조회 실패 (N번 시도): …`)
   - 기다리는 중 곡이 바뀌거나 작업이 취소되면 바로 멈추는 지금 동작 유지 (`lyricsKey == key` 확인)
   - 재시도 로그는 지금 형식 유지: `⚠️ 가사 조회 오류: … — N초 뒤 재시도`
3. **재시도 중 카드**: 첫 실패 때 카드 내용은 지금처럼 그대로(가사 도착 전 상태). 끝내 실패했을 때만 `가사 없음`으로 갱신, 도중에 성공하면 `가사 도착`으로 갱신 (지금과 같은 흐름이며 갱신은 `sendCard`로만)
4. 보고서 `docs/dev/reports/012-report.md` (상태: 검토 요청)

## Red 목록
대상: `LyricsRetryPolicy` (새 타입, 아래 시그니처)

| # | 입력 | 기대값 |
|---|---|---|
| 1 | `isTransient(LyricsError.http(503))` | true |
| 2 | `isTransient(LyricsError.http(500))` | true |
| 3 | `isTransient(LyricsError.http(429))` | true |
| 4 | `isTransient(LyricsError.http(400))` | false |
| 5 | `isTransient(URLError(.timedOut))` | true |
| 6 | `isTransient(URLError(.notConnectedToInternet))` | true |
| 7 | `isTransient(URLError(.cancelled))` | false |
| 8 | `isTransient(CancellationError())` | false |
| 9 | `delay(afterFailure: 1)`, `2`, `3`, `4`, `5` | 2, 5, 15, 30, 60 |
| 10 | `delay(afterFailure: 6)`, `7`, `0` | nil, nil, nil |

## 새 함수 시그니처
```swift
// LiveLyricsExperiment/LyricsService.swift
nonisolated enum LyricsRetryPolicy {
    /// 잠시 뒤 다시 시도하면 될 수 있는 오류인지 (서버 5xx·429·네트워크)
    static func isTransient(_ error: Error) -> Bool
    /// n번째 실패 뒤 기다릴 초. nil이면 더 시도하지 않음
    static func delay(afterFailure attempt: Int) -> TimeInterval?
}
```

## 주의
- `LyricsError`는 이미 있음 (`LyricsService.swift:110`). 새로 만들지 말 것
- 시간 계산·대기는 지금처럼 `Task.sleep`. 매초 깨우거나 타이머를 새로 두지 말 것

## 하지 말 것
- 카드 문구·`ContentState`(`LyricsActivityAttributes.swift`) 변경 금지
- 검색 4단계·제목 정리·연주곡 판단·재검색 간격(24시간) 규칙 변경 금지
- 끝내 실패한 곡을 검색 기록에 남기지 말 것 (현재 동작 유지)
- Spotify 폴링·한도 처리·위치 추적 변경 금지
- 테스트·계약 파일, `docs/plan/`, `CLAUDE.md` 수정 금지, git 명령 금지

## 완료 조건
- Red 10개 모두 통과, 빌드·테스트 명령 성공, `scripts/check.sh` 모두 ✅
- 보고서 작성 (상태: 검토 요청)

## 사용자가 아이폰에서 확인할 것
503은 일부러 만들 수 없으므로 **평소 사용 중 우연히 생기면** 확인한다. 평소 동작이 깨지지 않았는지가 우선.
1. 평소처럼 여러 곡 재생 → 싱크 가사 곡은 `🎵 가사 찾음 … 싱크 N줄` → `🪪 카드 갱신 — 가사 도착` (지금과 같음)
2. (생기면) `⚠️ 가사 조회 오류 … — 15초 뒤 재시도` 이상의 줄이 보이고, 같은 곡 재생 중 `가사 찾음`으로 이어지는지
3. (선택) 비행기 모드로 곡을 넘긴 뒤 몇 초 안에 끄기 → `⚠️ 가사 조회 오류` 뒤 같은 곡에서 가사 도착
