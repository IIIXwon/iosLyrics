# /task N — 지시서가 없으면 plan mode로 초안부터

## Context
질문: "로드맵에 할 일이 없는데 /task로 작업할 수 있어?" → 할 수 있다.
사용자 결정(2026-10-27): **N번 지시서가 없으면 plan mode로 먼저 초안을 쓰고, 승인받은 뒤 진행**한다.
지금 `/task` 스킬 ①은 "roadmap·decisions 기준으로 초안 → 승인"이라 roadmap이 비면 근거가 없고, 초안 단계와 실행 단계가 섞여 있다.

## 변경
**`.claude/skills/task/SKILL.md`**
- `argument-hint: <작업 번호>` → `<작업 번호> [하고 싶은 내용]`
- ① "없음 →" 줄을 다음으로 교체:
  - 없음 → **plan mode로 들어가(`EnterPlanMode`) 초안부터 쓴다.** 목적은 번호 뒤에 적은 내용이나 대화의 사용자 요청. 요청이 없으면 무엇을 할지 묻는다
  - plan 단계에서 관련 코드와 `roadmap.md`·`decisions.md`·`constraints.md`(하지 않음·금지 목록)를 읽기만 하고, 지시서 구성(목적 / 할 일 / Red 목록 / 새 함수 시그니처 / 주의 / 하지 말 것 / 완료 조건 / 아이폰 확인)대로 계획 파일에 쓴다
  - 사용자가 plan을 승인하면 그 내용을 `docs/plan/tasks/NNN-제목.md`(상태: `대기`)로 저장하고 브랜치·커밋 후 ②로
- `대기`·`수정 요청`일 때의 동작은 그대로

**`CLAUDE.md`** "🔁 작업 흐름"의 `/task N` ① 설명: "리드 지시서·브랜치" → "리드 지시서(없으면 plan mode로 초안 → 승인)·브랜치"

**메모리**: feedback `task-draft-in-plan-mode` + `MEMORY.md` 한 줄

## Git
- `main`에서 `chore/task-plan-mode` 브랜치 → `scripts/check.sh` → 커밋 `chore(skills): task 지시서가 없으면 plan mode로 초안`
- 이 계획 파일은 `docs/plan/task-plan-mode.md`로 옮겨 같이 커밋 (`plansDirectory`는 재시작 후 적용되는 듯)
- push·PR은 사용자 확인 후
