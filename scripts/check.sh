#!/usr/bin/env bash
# CLAUDE.md "코딩 규칙"·"⛔ 다시 시도하지 말 것" 중 도구로 잡을 수 있는 것과 Client ID 노출을 점검한다.
# 사용: scripts/check.sh  (개발 후, 커밋 전). 위반이 하나라도 있으면 exit 1.
set -u
cd "$(dirname "$0")/.." || exit 1
fail=0
ok()  { printf '✅ %s\n' "$1"; }
bad() { printf '❌ %s\n%s\n' "$1" "$2"; fail=1; }
SRC=(LiveLyricsExperiment Spotify LyricsWidget LyricsActivityAttributes.swift)

# 1. Live Activity 시작·갱신은 ExperimentController에서만 (CLAUDE.md WHY)
hits=$(grep -rnE --include='*.swift' '\.update\(ActivityContent|Activity(<[^>]*>)?\.request\(' "${SRC[@]}" \
  | grep -v '^LiveLyricsExperiment/ExperimentController.swift:' || true)
if [ -z "$hits" ]; then ok "Live Activity 시작·갱신은 ExperimentController에만 있음"
else bad "ExperimentController 밖에서 Live Activity를 시작·갱신함" "$hits"; fi

# 2. ObservableObject를 쓰는 파일은 import Combine (코딩 규칙)
missing=""
while IFS= read -r f; do
  [ -n "$f" ] && ! grep -q '^import Combine' "$f" && missing="$missing$f"$'\n'
done < <(grep -rlE --include='*.swift' 'ObservableObject' "${SRC[@]}" || true)
if [ -z "$missing" ]; then ok "ObservableObject 파일에 import Combine 있음"
else bad "import Combine 없음" "$missing"; fi

# 3. 제외된 방식 (⛔ 무음 오디오로 백그라운드 유지)
hits=$(grep -rnE 'SilentAudio' "${SRC[@]}" LiveLyricsExperiment.xcodeproj/project.pbxproj || true)
if [ -z "$hits" ]; then ok "제외된 방식 흔적 없음"
else bad "제외된 방식 흔적이 있음" "$hits"; fi

# 3-1. Spotify iOS SDK는 SpotifyRemote.swift에서만 (작업 025: 보조 출처, 감싸는 파일 하나)
hits=$(grep -rnE --include='*.swift' 'SPTAppRemote|import SpotifyiOS' "${SRC[@]}" \
  | grep -v '^Spotify/SpotifyRemote.swift:' || true)
if [ -z "$hits" ]; then ok "Spotify iOS SDK는 SpotifyRemote.swift에만 있음"
else bad "SpotifyRemote.swift 밖에서 Spotify iOS SDK를 씀" "$hits"; fi

# 4. Spotify Client ID가 git에 들어가지 않는지 (스테이징된 내용 기준)
hits=""
git diff --cached --name-only | grep -qx 'Spotify/SpotifySecrets.swift' && hits="Spotify/SpotifySecrets.swift가 스테이징됨"$'\n'
cid=$(git grep --cached -nE 'clientID[^"]*"[0-9a-fA-F]{32}"' -- '*.swift' 2>/dev/null | sed -E 's/"[0-9a-fA-F]{32}"/"<숨김>"/' || true)
[ -n "$cid" ] && hits="$hits$cid"
if [ -z "$hits" ]; then ok "Client ID가 스테이징·커밋 대상에 없음"
else bad "Client ID가 git에 들어갈 수 있음 (git restore --staged <파일>)" "$hits"; fi

# 5. swift test 대상 순수 로직(Logic/)은 Foundation만 import (작업 024, Mac에서 컴파일되도록)
# 하위 폴더 포함, `@preconcurrency import X`·`import struct X.Y` 형태도 잡는다
hits=$(grep -rnE --include='*.swift' '^[[:space:]]*(@[A-Za-z_]+[[:space:]]+)*import[[:space:]]' LiveLyricsExperiment/Logic 2>/dev/null \
  | grep -vE ':[0-9]+:import Foundation[[:space:]]*$' || true)
if [ -z "$hits" ]; then ok "Logic/ 파일은 import Foundation만 씀"
else bad "Logic/ 파일에 Foundation 밖 import가 있음 (swift test에서 컴파일 안 됨)" "$hits"; fi

exit $fail
