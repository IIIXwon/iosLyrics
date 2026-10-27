# 아키텍처

```
Spotify Web API (3초 폴링) ─▶ NowPlayingService ─▶ 재생 위치 계산 (폴링 사이엔 경과 시간으로 추정)
                                                        │
LRCLIB (곡 변경 시 1회)  ─▶ LyricsService (LRC 파싱) ─▶ 현재 줄 계산
                                                        │
                                   ExperimentController ─▶ Activity.update (바뀐 게 있을 때만)
                                                        │
LocationKeepAlive (저전력 위치 추적) ── 앱을 백그라운드에서 살려 둠
```

## 데이터 출처
- **재생 정보**: Spotify Web API `GET /v1/me/player/currently-playing` (PKCE 로그인, 개발자 모드)
- **가사**: LRCLIB (`https://lrclib.net/api/get`, `/api/search`) — 무료 커뮤니티 DB, 조회만

## 잠금화면 카드
- **시간 표시**: `Text(timerInterval:)`, `ProgressView(timerInterval:)` → iOS가 스스로 흘려 보냄. 앱은 `trackStart`(곡 0초 시각)만 넘김
- **갱신 조건**: 곡 변경 / 재생·일시정지 / 위치가 0.7초 이상 어긋남 / 가사 줄 변경
- **`ContentState`** (`LyricsActivityAttributes.swift`):
  previous / current / next / trackInfo / isPlaying / trackStart / trackEnd / pausedPosition / duration
  - 실험용이던 `updateCount`·`updatedAt`과 번역용 `translation`은 정리하면서 제거함
- **누르는 곳** (작업 009·010)
  - ▶︎ 버튼(일시정지 때만): `ResumeLyricsIntent` → `resumeFromCard()` (잠금 해제 불필요)
  - 나머지 영역: `widgetURL(livelyrics://open-spotify)` → 잠금 해제 → 앱이 `spotify:`를 열고, 뒤에서 2초마다 기기 목록 확인(최대 20초) → 기억한 기기·스마트폰 기기가 나타나면 재생 요청 1번 → 즉시 조회. 한도 차단 중·이미 재생 중이면 재생 요청 안 함
- 재생 정보는 **Web API만** 사용. Spotify iOS SDK는 009에서 실험 후 010에서 제거 (우리 앱이 화면에 있을 때만 재연결돼 이득이 작음)

## 재생 정보 (NowPlayingService)
- 폴링 간격: 재생 중 **3초** · 일시정지 15초 · 곡 없음 10초 (작업 008, 1초 폴링으로 하루 쓰면 호출 한도 초과)
- 곡 변경·일시정지·seek 감지, 폴링 사이엔 경과 시간으로 위치 추정

## 가사 (LyricsService, 앱 타깃)

**저장 폴더** — 이 기기 안에만 저장 (`LyricsStore`)
```
Application Support/LiveLyrics/
  ├─ synced/  싱크 가사  "아티스트 - 제목.lrc"
  └─ plain/   일반 가사  "아티스트 - 제목.txt"  (싱크 가사를 못 찾았을 때만)
```
- 곡이 바뀌면 `synced/`에 저장본이 있는지 먼저 확인 → 있으면 인터넷 조회 없이 사용
- 싱크 가사를 새로 구하면 `synced/`에 저장하고, 같은 곡의 `plain/` 파일은 지움
- 싱크 가사가 없고 일반 가사만 있으면 `plain/`에 저장 (다음에 다시 검색해서 싱크 가사가 생겼는지 확인)
- 인터넷 조회가 끝내 실패하면 `plain/` 저장본이 있을 때 그것을 사용
- 연주곡·못 찾음은 저장하지 않음

**검색 순서** (`LyricsService.find`, 모든 단계에 곡 길이 차이 10초 이내 조건)
1. `/api/get` — 원래 제목·아티스트·앨범·길이
2. `/api/search` — 원래 제목 + 아티스트
3. `/api/search` — 정리한 제목 + 아티스트 (`TitleCleaner.clean`)
   - 떼는 것: `(feat. …)`, `(with …)`, `- Remastered`, `- 2011 Remaster`, `(Radio Edit)` 등의 꼬리
   - 떼지 않는 것: `Live`, `Remix`, `Acoustic` 등 (다른 버전이라 타이밍이 다름)
4. `/api/search` — 정리한 제목 + 첫 번째 아티스트만 (Spotify는 아티스트를 쉼표로 이어서 줌)
- 같은 검색어는 건너뜀. 싱크 가사를 찾으면 멈추고, 일반 가사만 나오면 **다음 단계까지 계속 검색**해서 싱크 가사를 먼저 찾아봄
- 우선순위: 싱크 가사 → 일반 가사(`plainLyrics`) → 연주곡(`instrumental == true`) → 없음

**카드 표시** (`ExperimentController.makeState`, `ContentState`는 바꾸지 않고 문구만 바꿈)
| 결과 | 카드 |
|---|---|
| 싱크 가사 | 제목·아티스트 / 이전 줄 / 현재 줄 / 다음 줄 (줄이 바뀔 때만 갱신) |
| 일반 가사만 | 제목·아티스트 / **"싱크 가사가 없어요"** / "일반 가사만 있어서 저장해 뒀어요" (가사는 카드에 표시하지 않음) |
| 연주곡 | 제목·아티스트 / "🎼 연주곡" |
| 못 찾음 | 아티스트 / 제목 / 앨범 |

**기타**
- `LRCParser`로 LRC 파싱. 싱크 가사는 파싱한 줄 목록만 메모리에 보관
- 조회 오류(HTTP 5xx 등)는 2초·5초 뒤 재시도 (최대 3번), 오류 로그에 상태 코드 표시
- 다음 줄 시각에 맞춰 `lineTask`가 카드 갱신을 예약 → 1초 폴링 사이에 줄이 바뀌어도 제때 반영
- 싱크 보정: ±0.25초 단위, ±5초 범위, `UserDefaults` 저장. 저장값이 없으면 기본 **+0.25초**

**로그**
- `🔎 가사 검색` → `🎵 가사 찾음 (3단계: 정리한 제목, 싱크 N줄)` 또는 `(…, 일반 가사만 — 싱크 없음)`
- `💾 가사 저장 → LiveLyrics/synced/` / `💾 저장된 싱크 가사 사용`
- 못 찾았을 때 `⚠️ 가사 없음: 제목 – 아티스트`, 연주곡은 `🎼 연주곡으로 등록된 곡이에요`

## 백그라운드 유지 (LocationKeepAlive)
- 정확도 3km, distanceFilter 최대 (저전력)
- 재생이 멈추고 3분(`idleGrace`) 지나면 위치 추적을 끄고, 재생 중으로 바뀌면 다시 켬
  - 알려진 한계: 끈 뒤엔 앱이 일시 중단되므로, 재생을 재개해도 **앱 화면을 열기 전까지 카드가 갱신되지 않음**
