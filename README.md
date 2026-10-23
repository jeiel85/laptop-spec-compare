# 내 기기 측정하고 다른 사람들과 순위 비교

페이지를 연 노트북이나 휴대폰의 성능을 자동으로 재고, 다른 사람들이 올린 기록 사이에서 몇 위인지 보여주는 페이지예요. 점수는 기준 노트북(Intel Core 5 210H, 32GB)을 1,000점으로 놓고 계산해요.

- **자동으로 확인하는 것:** 기기 종류(노트북, 휴대폰, 태블릿), CPU 스레드 수, 그래픽(NVIDIA 외장 그래픽 포함), 화면 해상도와 주사율, 운영체제
- **자동으로 측정하는 것:** CPU 싱글코어, 멀티코어 성능 (약 6초, 기준 노트북 = 1,000점). 탭이 화면에 보일 때만 재요.
- **직접 고르는 것:** CPU(칩) 모델, 메모리 용량. 브라우저가 알려주지 않아요. 노트북은 페이지 아래의 PowerShell 명령어로 정확한 값을 채울 수 있어요.
- **보여주는 것:** 이 기기로 할 수 있는 일(쾌적 / 제한적 / 어려움), 항목별 비교
- **다른 사람들과 비교:** 원하면 "점수 올리기"로 점수를 올려서, 다른 기기들 사이에서 몇 위인지와 상위 20개 목록을 볼 수 있어요 (Supabase).

측정 결과와 고른 값은 그 브라우저에만 저장돼요. "점수 올리기"를 누를 때만 닉네임(선택), 기기 종류, 운영체제, CPU·그래픽 이름, 스레드 수, 메모리, 점수를 점수판에 보내요.

## 파일

| 파일 | 내용 |
|---|---|
| `spec-compare.html` | 페이지 원본. 수정은 여기서 해요 (Claude 아티팩트로도 게시돼 있어요) |
| `build.ps1` | 원본으로 `index.html`을 만들고, 이 폴더를 `laptop-spec-compare.zip`으로 묶어요 |
| `index.html`, `.nojekyll` | 빌드 결과. GitHub Pages가 보여주는 페이지예요. 직접 고치지 않아요 |
| `og-image.png`, `assets/og-card.html` | 링크 미리보기 이미지(1200×630)와 그 원본 |
| `docs/leaderboard-design.md` | 다른 사람들과 점수를 비교하는 기능(Supabase) 설계서 |
| `supabase/migrations/` | 점수판 DB에 적용한 SQL (표, 권한, 뷰, 함수, 기준 기기) |
| `.github/workflows/supabase-keepalive.yml` | 3일마다 점수판을 한 번 읽어서 Supabase 무료 프로젝트가 일시정지되지 않게 해요 |
| `laptop-spec-compare.zip` | 이 폴더 전체. 다른 PC로 옮기는 용도 |

원본을 고친 뒤에는 이 폴더에서 다시 빌드해요.

```
powershell -ExecutionPolicy Bypass -File .\build.ps1
```

## 다른 PC로 옮겨서 GitHub Pages로 배포하기

1. `laptop-spec-compare.zip`을 옮겨서 압축을 풀어요.
2. GitHub에서 새 저장소를 만들어요. 예: `laptop-spec-compare`, 공개(Public)
3. 압축을 푼 파일과 폴더를 전부 저장소 맨 위에 올려요.
   - 웹에서는 저장소 화면의 **Add file → Upload files**에 끌어다 놓으면 돼요. `docs` 폴더도 같이 끌어다 놓으면 폴더째 올라가요.
   - Git을 쓰면 그 폴더에서 `git init` 후 커밋하고 push해요.
   - `.nojekyll`은 탐색기에서 안 보일 수 있지만, 없어도 페이지는 동작해요.
4. 저장소의 **Settings → Pages**에서 Source를 **Deploy from a branch**로, Branch를 **main / (root)**로 고르고 Save를 눌러요.
5. 1~2분 뒤 `https://<GitHub 아이디>.github.io/laptop-spec-compare/`에서 열려요.

공개 저장소와 Pages는 누구나 볼 수 있어요. 페이지에는 기준 노트북의 CPU, 메모리 용량, 그래픽, 화면 사양이 들어 있어요(모델명은 넣지 않아요).

## 미리보기 이미지

Threads·카카오톡 등에 링크를 붙이면 `og-image.png`가 보여요. `assets/og-card.html`을 고친 뒤 이 폴더에서 다시 만들어요.

```
& 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe' --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 --window-size=1200,630 --virtual-time-budget=8000 --screenshot="$PWD\og-image.png" "file:///$($PWD -replace '\\','/')/assets/og-card.html"
```

## 점수판 (Supabase)

- 프로젝트: `laptop-spec-compare` (ref `ijemtaegzsecsqqcgeza`, 서울 리전, Free 플랜)
- 페이지의 `LEADERBOARD`에는 공개용 키(`sb_publishable_...`)만 넣어요. `service_role`·`sb_secret_...` 키는 절대 넣지 않아요.
- 이상한 점수 지우기: Supabase 대시보드 → Table Editor → `scores` → 행 선택 → Delete
- 일주일 넘게 활동이 없어서 일시정지되면 대시보드에서 Restore를 눌러요. 데이터는 남아 있어요.
- 측정 코드(`WORKER_SRC`)나 측정 순서를 바꾸면 `BENCH_VERSION`을 올리고, DB 정책과 `score_stats`의 `bench_version` 조건도 새 마이그레이션으로 같이 바꿔요.

## 기준 노트북 기준값

`spec-compare.html`의 `A.bench`에 기준 노트북에서 잰 CPU 원점수가 들어 있어요 (2026-10-23, 앱 안 브라우저 Chromium, 3회 중앙값). 다시 재려면 기준 노트북에서 페이지를 열고, 측정이 끝난 뒤 브라우저 콘솔에서 `__lastBench`를 확인해 그 값으로 바꾸면 돼요.
