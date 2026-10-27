# 플랜 모드 계획 파일을 프로젝트 안(docs/plan/plans/)에 저장하기

## Context
사용자 요청(2026-10-27): 이 프로젝트에서 플랜 모드로 쓴 계획은 `~/.claude/plans/`가 아니라 프로젝트 안에 둔다.
CLAUDE.md "📝 문서 관리" 기준으로 계획 문서는 리드가 관리하는 `docs/plan/` 아래에 둔다. 단 `docs/plan/tasks/`는 `NNN-제목.md` 지시서 전용이라 섞지 않고 **`docs/plan/plans/`** 하위 폴더를 새로 쓴다.

## 변경
1. **`.claude/settings.json`** (프로젝트 설정, git에 포함)에 `"plansDirectory": "docs/plan/plans"` 추가
   - 실행 전에 `update-config` 스킬로 설정 키 이름과 경로 형식(프로젝트 기준 상대 경로)을 확인
   - 기존 `permissions`·`hooks`는 그대로
2. **`docs/plan/plans/`** 폴더 생성, 이번 세션의 계획 파일(013 마무리 계획)을 여기로 옮김: `~/.claude/plans/docs-plan-roadmap-md-2-happy-pixel.md` → `docs/plan/plans/013-wrap-up.md` (원본 삭제)
3. **`CLAUDE.md`**
   - "계약 (리드만 수정)" 표의 `docs/plan/**` 설명에 "플랜 모드 계획(`plans/`)" 추가
   - "📝 문서 관리"의 `docs/plan/` 줄에 "플랜 모드 계획은 `docs/plan/plans/` (설정 `plansDirectory`)" 추가
4. **메모리**: feedback 메모리 `plan-files-in-project` 작성 + `MEMORY.md`에 한 줄 (설정이 적용 안 되는 경우에도 계획을 `docs/plan/plans/`에 쓰도록)

## Git
- 지금 브랜치 `task/013-card-simplify`는 013 전용이라 섞지 않음 → `main`에서 `chore/plans-directory` 브랜치로 커밋 `chore: 플랜 모드 계획을 docs/plan/plans에 저장`
- add 대상: `.claude/settings.json`, `CLAUDE.md`, `docs/plan/plans/013-wrap-up.md` (`.claude/skills/judge/SKILL.md` 제외)
- ⚠️ `CLAUDE.md`·`LyricsActivityAttributes.swift` 주석 수정은 013 브랜치에 이미 커밋됨 → 새 브랜치의 CLAUDE.md 수정과 병합 시 충돌 가능성 낮음(다른 줄)
- push·PR은 사용자 확인 후

## 확인
- `cat .claude/settings.json`으로 JSON 형식 확인 (`python3 -m json.tool`)
- 다음 플랜 모드 진입 시 계획 파일 경로가 `docs/plan/plans/…`로 안내되는지 (설정은 새 세션부터 적용될 수 있음 → 안 되면 메모리 규칙대로 직접 그 경로에 작성)
