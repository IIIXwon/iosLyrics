# 플랜 모드 계획 위치를 docs/plan/으로 바로잡기

## Context
사용자 지적(2026-10-27): 이 프로젝트에서는 "plans" 폴더가 곧 **`docs/plan/`** 이다. 직전 작업에서 하위 폴더 `docs/plan/plans/`를 새로 만든 것은 잘못.
→ 플랜 모드 계획 파일은 `docs/plan/` 바로 아래에 둔다 (roadmap·decisions·constraints와 같은 자리).

※ 지금 세션은 `task/013-card-simplify` 브랜치라 `plansDirectory` 설정이 없어서 시스템이 이 계획을 `~/.claude/plans/`에 쓰게 했다. 실행 단계에서 이 파일도 `docs/plan/`으로 옮긴다.

## 변경 (브랜치 `chore/plans-directory`에서, 새 커밋)
1. **`.claude/settings.json`**: `"plansDirectory": "docs/plan/plans"` → `"docs/plan"`
2. **계획 파일 이동**
   - `git mv docs/plan/plans/plans-directory.md docs/plan/plans-directory.md` → 빈 `docs/plan/plans/` 폴더 삭제
   - 이번 계획 `~/.claude/plans/docs-plan-roadmap-md-2-happy-pixel.md` → `docs/plan/plans-directory-fix.md`로 옮기고 원본 삭제
3. **`CLAUDE.md`**
   - "계약" 표: `플랜 모드 계획(\`plans/\`)` → `플랜 모드 계획`
   - "📝 문서 관리": `docs/plan/plans/` 줄 → "플랜 모드 계획도 `docs/plan/`에 둔다 (`.claude/settings.json`의 `plansDirectory`). `~/.claude/plans/`에 쓰지 않는다"
4. **메모리 `plan-files-in-project.md`·`MEMORY.md`**: 경로를 `docs/plan/`으로 고치고, "plans = 이 프로젝트의 `docs/plan`" 이유를 적음

## Git
- `git switch chore/plans-directory` → 수정 → `scripts/check.sh` → 커밋 `chore: 플랜 모드 계획 위치를 docs/plan으로 수정`
- add: `.claude/settings.json`, `CLAUDE.md`, `docs/plan/plans-directory.md`, `docs/plan/plans/plans-directory.md`(삭제분), `docs/plan/plans-directory-fix.md`
- 끝나면 `task/013-card-simplify`로 다시 전환 (아이폰 013 확인용 코드 유지)
- push·PR은 사용자 확인 후

## 확인
- `python3 -m json.tool .claude/settings.json`, `ls docs/plan` (plans/ 폴더 없음), `grep -n "plans/" CLAUDE.md` 결과 없음
