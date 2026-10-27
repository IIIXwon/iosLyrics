#!/usr/bin/env bash
# PreToolUse(Bash): main(master) 브랜치로 직접 push하는 명령을 차단한다. main은 PR + squash merge로만 바꾼다.
# 명령줄을 ; && || | 줄바꿈으로 나눠 git push 구간만 검사한다(다른 명령의 "main" 인자는 무시).
set -u
cmd="$(jq -r '.tool_input.command // empty')"

block() {
  echo "차단: main 브랜치 직접 push는 금지입니다. task/<번호>-<이름> 브랜치에서 PR을 만드세요. ($1)" >&2
  exit 2
}

while IFS= read -r seg; do
  echo "$seg" | grep -Eq '(^|[[:space:]])git([[:space:]]+-[^[:space:]]+([[:space:]]+[^-[:space:]][^[:space:]]*)?)*[[:space:]]+push([[:space:]]|$)' || continue
  rest="$(echo "$seg" | sed -E 's/.*[[:space:]]push([[:space:]]|$)/ /')"

  # refspec에 main/master (main, HEAD:main, +main, refs/heads/main), --all/--mirror
  echo " $rest " | grep -Eq '[[:space:]:+/](main|master)[[:space:]]' && block "대상 ref가 main"
  echo " $rest " | grep -Eq '[[:space:]]--(all|mirror)[[:space:]]' && block "--all/--mirror"

  # refspec 없이 push하면 현재 브랜치가 대상이다
  args="$(echo "$rest" | tr ' ' '\n' | grep -v '^-' | grep -v '^$' | wc -l | tr -d ' ')"
  if [ "$args" -le 1 ]; then
    branch="$(git -C "${CLAUDE_PROJECT_DIR:-$(pwd)}" rev-parse --abbrev-ref HEAD 2>/dev/null)"
    case "$branch" in main | master) block "현재 브랜치가 $branch" ;; esac
  fi
done < <(printf '%s\n' "$cmd" | sed -E 's/(&&|\|\||;|\|)/\n/g')
exit 0
