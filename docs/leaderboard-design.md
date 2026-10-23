# 점수 비교판 설계서

측정한 CPU 점수를 저장해서 다른 사람들의 기기와 비교하는 기능의 설계예요. GitHub Pages(정적 페이지)와 Supabase 무료 플랜으로 만들어요.

- 작성: 2026-10-23, 기준 노트북에서 설계만 하고 구현은 개인 PC에서 해요.
- 구현: 2026-10-23 완료. 실제 적용한 SQL은 `supabase/migrations/`에 있어요. 아래 4-1과 달리 `revoke all`로 anon의 기본 권한을 모두 회수하고, 트리거 함수의 직접 실행 권한도 막았어요.
- 이 문서만 보고 구현할 수 있게 SQL, 워크플로, 화면 문구, 확인 방법을 모두 넣었어요. Claude Code에 이 파일을 주고 "설계서대로 구현해줘"라고 해도 돼요.

---

## 1. 목표와 범위

**할 일**
- 측정이 끝나면 사용자가 원할 때만 점수를 올려요. 자동으로 올리지 않아요.
- 올린 점수로 "측정한 기기 N대 중 상위 X%"와 상위 목록을 보여줘요.
- 노트북과 휴대폰·태블릿을 나눠서 볼 수 있어요.
- 같은 기기는 마지막으로 올린 점수 하나만 순위에 쓰여요.

**하지 않을 일**
- 로그인이나 회원가입은 없어요. 닉네임만 선택으로 받아요.
- 장난 점수를 완전히 막지는 못해요. 범위 검사와 올리기 횟수 제한까지만 하고, 나머지는 대시보드에서 지워요.
- Claude 아티팩트 버전에서는 점수판이 동작하지 않아요. 아티팩트는 외부 서버로 요청을 보낼 수 없어서, GitHub Pages 주소에서만 써요.

---

## 2. 지금 페이지 구조 (구현 전에 알아둘 것)

| 파일 | 역할 |
|---|---|
| `spec-compare.html` | 원본. 아티팩트 형식이라 `<html>`, `<head>`, `<body>` 태그가 없어요 |
| `build.ps1` | 원본을 감싸서 `index.html`을 만들고 프로젝트를 zip으로 묶어요 |
| `index.html` | 빌드 결과. GitHub Pages가 보여주는 페이지예요. 직접 고치지 않아요 |

`spec-compare.html`의 `<script>` 안에서 이번 작업과 관련된 부분이에요.

| 이름 | 내용 |
|---|---|
| `A.bench` | 기준 노트북 기준 원점수 `{ single: 1.41, multi: 7.95 }`. 브라우저 안 Chromium에서 3회 잰 중앙값 |
| `WORKER_SRC` | CPU 측정 코드(Web Worker). 결과는 "ms당 처리한 묶음 수" 원점수예요 |
| `runBench()` | 싱글 2회, 멀티 1회를 재서 `state.bench = { single, multi, threads, at }`에 넣어요 |
| `buildB()` | 지금 기기 정보를 모아요. 점수는 `원점수 / A.bench × 1000`이라 기준 노트북이 1,000점이에요 |
| `render()` | 화면 전체를 다시 그려요 |
| `state` | `{ det, bench, cpu, ram, gpu, gpuAuto, exact }`. `det.kind`는 `'laptop' \| 'phone' \| 'tablet'` |
| `load()` / `save()` | `localStorage`의 `spec-compare-v2` 키에 저장해요 |

측정 코드(`WORKER_SRC`)나 측정 방식이 바뀌면 점수끼리 비교할 수 없어요. 그래서 `BENCH_VERSION` 상수를 새로 두고 DB에도 같이 저장해요 (4장).

---

## 3. 전체 흐름

```
[사용자 브라우저]                                [Supabase]
 1. 페이지 열기 → 자동 감지 → CPU 측정
 2. "내 점수 올리기" 누름  ── POST /rest/v1/scores ──▶  scores 표 (추가만 허용)
 3. 순위·목록 보기          ◀─ GET  /rest/v1/latest_scores ─  기기별 최신 점수 뷰
                            ◀─ POST /rest/v1/rpc/score_stats ─ 상위 % 계산 함수
[GitHub Actions] 3일마다    ── GET  /rest/v1/latest_scores ──▶  일시정지 방지
```

---

## 4. 데이터베이스 (Supabase SQL Editor에서 한 번에 실행)

### 4-1. 표, 권한, 뷰, 함수

```sql
-- 점수 기록. 한 번 올린 기록은 고치거나 지울 수 없어요 (관리자는 대시보드에서 지울 수 있어요)
create table public.scores (
  id            bigint generated always as identity primary key,
  created_at    timestamptz not null default now(),
  device_id     uuid not null,                 -- 브라우저마다 만든 임의 ID. 밖으로 보여주지 않아요
  nickname      text check (nickname is null or char_length(nickname) between 1 and 20),
  kind          text not null check (kind in ('laptop', 'phone', 'tablet')),
  os            text check (char_length(os) <= 40),
  cpu           text check (char_length(cpu) <= 60),   -- 사용자가 고른 CPU/칩. 모르면 null
  gpu           text check (char_length(gpu) <= 80),
  threads       int  not null check (threads between 1 and 256),
  ram_gb        int  check (ram_gb between 1 and 1024),
  single_pts    int  not null check (single_pts between 10 and 5000),
  multi_pts     int  not null check (multi_pts between 10 and 50000),
  gpu_pts       int  check (gpu_pts between 0 and 50000),
  single_raw    real not null check (single_raw > 0),  -- 기준값이 바뀌어도 다시 계산할 수 있게 원점수도 둬요
  multi_raw     real not null check (multi_raw > 0),
  bench_version smallint not null,
  browser       text check (char_length(browser) <= 40)
);

create index scores_device_idx on public.scores (device_id, created_at desc);

-- 행 단위 보안: 익명 사용자는 추가만 할 수 있어요. 읽기는 아래 뷰로만 해요
alter table public.scores enable row level security;

create policy "anyone can add a score"
  on public.scores for insert to anon
  with check (bench_version = 1);

revoke select, update, delete on public.scores from anon, authenticated;
grant insert on public.scores to anon;   -- 기본으로 주어져 있어도 확실히 해 둬요

-- 기기별 최신 점수. device_id 대신 해시(device_key)만 보여줘서,
-- 남의 device_id로 점수를 덮어쓰지 못하게 해요.
-- 일부러 뷰 소유자 권한으로 실행되게 둬요(security_invoker 안 씀). Supabase 검사기가 경고해도 의도한 거예요.
create view public.latest_scores as
  select distinct on (device_id)
    id, created_at,
    encode(sha256(convert_to(device_id::text, 'UTF8')), 'hex') as device_key,
    nickname, kind, os, cpu, gpu, threads, ram_gb,
    single_pts, multi_pts, gpu_pts, bench_version, browser
  from public.scores
  order by device_id, created_at desc;

grant select on public.latest_scores to anon;

-- 내 점수가 상위 몇 %인지
create or replace function public.score_stats(p_multi int, p_single int, p_kind text default null)
returns json
language sql stable
set search_path = public
as $$
  select json_build_object(
    'total',        count(*),
    'below_multi',  count(*) filter (where multi_pts  < p_multi),
    'below_single', count(*) filter (where single_pts < p_single)
  )
  from public.latest_scores
  where bench_version = 1
    and (p_kind is null
         or (p_kind = 'laptop' and kind = 'laptop')
         or (p_kind = 'mobile' and kind in ('phone', 'tablet')));
$$;

grant execute on function public.score_stats(int, int, text) to anon;

-- 같은 기기에서 1시간에 5번까지만 올릴 수 있어요
create or replace function public.limit_score_inserts()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if (select count(*) from public.scores
      where device_id = new.device_id
        and created_at > now() - interval '1 hour') >= 5 then
    raise exception 'too many submissions from this device';
  end if;
  return new;
end;
$$;

create trigger scores_rate_limit
  before insert on public.scores
  for each row execute function public.limit_score_inserts();
```

### 4-2. 기준 기기 넣기 (선택)

순위에 기준 노트북을 기준으로 보이게 해요. SQL Editor는 관리자 권한이라 위의 제한 없이 들어가요.

```sql
insert into public.scores
  (device_id, nickname, kind, os, cpu, gpu, threads, ram_gb,
   single_pts, multi_pts, gpu_pts, single_raw, multi_raw, bench_version, browser)
values
  ('00000000-0000-4000-8000-000000000001', '기준 노트북 (1,000점)', 'laptop', 'Windows 11',
   'Core 5 210H', 'Intel Graphics (48EU)', 12, 32,
   1000, 1000, 1050, 1.41, 7.95, 1, 'Chromium');
```

### 4-3. 관리

- 이상한 점수 지우기: Table Editor → `scores` → 행 선택 → Delete
- 측정 방식을 바꾸면 `BENCH_VERSION`을 2로 올리고, 4-1의 정책(`bench_version = 1`)과 `score_stats`의 조건도 같이 바꿔요.

---

## 5. 페이지 수정 (`spec-compare.html`)

### 5-1. 설정 값

`<script>` 맨 위, `const A = {...}` 옆에 둬요. 값이 비어 있으면 점수판 섹션 전체를 숨겨요.

```js
// Supabase 점수판. 비워 두면 점수판을 숨겨요. key는 공개용 키(publishable 또는 anon)만 넣어요
const LEADERBOARD = { url: '', key: '' }; // 예: { url: 'https://abcd1234.supabase.co', key: 'sb_publishable_...' }
const BENCH_VERSION = 1; // WORKER_SRC나 측정 순서를 바꾸면 올려요
```

**공개용 키만 넣어요.** `service_role`이나 `sb_secret_...` 키를 넣으면 누구나 DB를 지울 수 있어요.

### 5-2. 기기 ID

`localStorage`에 한 번 만들어 두고 계속 써요. 페이지 데이터를 지우면 새 기기로 취급돼요.

```js
function deviceId() {
  try {
    let id = localStorage.getItem('spec-compare-device-id');
    if (!id) { id = crypto.randomUUID(); localStorage.setItem('spec-compare-device-id', id); }
    return id;
  } catch (e) { return crypto.randomUUID(); }
}
// 목록에서 내 기기를 강조할 때 쓰는 값. DB의 device_key와 같은 방식(sha256 hex)이에요
async function deviceKey() {
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(deviceId()));
  return [...new Uint8Array(buf)].map(b => b.toString(16).padStart(2, '0')).join('');
}
```

### 5-3. Supabase 요청

라이브러리 없이 `fetch`로 REST API를 불러요.

```js
async function sb(path, opts = {}) {
  const res = await fetch(`${LEADERBOARD.url}/rest/v1/${path}`, {
    ...opts,
    headers: { apikey: LEADERBOARD.key, 'Content-Type': 'application/json', ...(opts.headers || {}) },
  });
  if (!res.ok) throw new Error(`${res.status} ${await res.text()}`);
  return res.status === 204 ? null : res.json();
}
```

> **구현할 때 확인:** 새 형식의 공개 키(`sb_publishable_...`)는 `apikey` 헤더만 쓰면 돼요. 예전 `anon` 키(JWT)를 쓰면 `Authorization: Bearer <키>` 헤더도 함께 넣어야 할 수 있어요. 구현하는 날 Supabase 문서에서 한 번 확인하세요.

### 5-4. 점수 올리기

`buildB()` 결과와 `state`로 한 행을 만들어요. 측정이 안 끝났거나(`state.bench` 없음) 측정값이 아니면(`b.measured === false`) 버튼을 끄세요.

```js
async function uploadScore(nickname) {
  const b = buildB();
  const row = {
    device_id: deviceId(),
    nickname: nickname.trim().slice(0, 20) || null,
    kind: state.det.kind,
    os: (state.det.os || '').slice(0, 40) || null,
    cpu: b.cpuLabel || null,
    gpu: b.gpu ? b.gpu.label : (b.gpuName || null),
    threads: b.threads,
    ram_gb: b.ramGB || null,
    single_pts: Math.round(b.single),
    multi_pts: Math.round(b.multi),
    gpu_pts: b.gpu ? b.gpu.score : null,
    single_raw: state.bench.single,
    multi_raw: state.bench.multi,
    bench_version: BENCH_VERSION,
    browser: browserName(), // 예: navigator.userAgentData.brands에서 "Chrome 130" / "Edge 130", 없으면 UA에서 "Safari"
  };
  await sb('scores', { method: 'POST', headers: { Prefer: 'return=minimal' }, body: JSON.stringify(row) });
}
```

- 1시간에 5번 넘게 올리면 서버가 오류를 돌려줘요. 응답 본문에 `too many submissions`가 있으면 "잠시 후 다시 올려 주세요"를 보여줘요.
- 범위 검사에 걸리면(예: 측정이 너무 빨리 끝나 점수가 비정상) "점수가 정상 범위를 벗어나서 올리지 못했어요. 다시 측정해 주세요"를 보여줘요.

### 5-5. 순위와 목록 읽기

```js
// 상위 %  (kind: null = 전체, 'laptop', 'mobile')
const stats = await sb('rpc/score_stats', {
  method: 'POST',
  body: JSON.stringify({ p_multi: Math.round(b.multi), p_single: Math.round(b.single), p_kind: kind }),
});
// 상위 % = 100 - below / total × 100  (total이 0이면 "아직 기록이 없어요")

// 상위 20개
const filter = kind === 'laptop' ? '&kind=eq.laptop' : kind === 'mobile' ? '&kind=in.(phone,tablet)' : '';
const rows = await sb(`latest_scores?select=device_key,nickname,kind,cpu,gpu,threads,single_pts,multi_pts,created_at&bench_version=eq.${BENCH_VERSION}&order=multi_pts.desc&limit=20${filter}`);
```

- 페이지를 열 때 한 번, 점수를 올린 직후 한 번, 필터를 바꿀 때 읽어요. 계속 다시 읽지는 않아요.
- 요청이 실패하면(아티팩트 버전, 오프라인, Supabase 일시정지) 섹션에 "점수판에 연결하지 못했어요"만 보여주고 나머지 페이지는 그대로 둬요.

---

## 6. 화면 설계

"이 기기로 할 수 있는 것" 섹션 바로 다음에 **"다른 사람들과 비교"** 섹션을 넣어요. 기존 토큰(`--a`, `--b`, `--good` 등)과 `.table`, `.chip`, `.pill` 스타일을 그대로 써요.

```
다른 사람들과 비교
측정한 기기 128대 중 이 노트북은 멀티코어 상위 23%, 싱글코어 상위 41%예요.

[전체] [노트북] [휴대폰·태블릿]          ← 필터 칩

 순위  닉네임        기기     CPU              멀티     싱글
  1   익명          노트북   i7-14700HX       2,710    1,190
  2   jeiel의 LOQ   노트북   Ryzen 7 8845HS   1,580    1,050   ← 내 기기 행은 주황 테두리
  …
  9   기준 노트북 (1,000점) 노트북 Core 5 210H     1,000    1,000   ← 파란 점

┌ 내 점수 올리기 ─────────────────────────────┐
│ 닉네임 (선택) [__________]  [점수 올리기]       │
│ 올라가는 정보: 닉네임, 기기 종류, 운영체제, CPU·그래픽 이름, │
│ 스레드 수, 메모리, 점수. 이름이나 위치는 보내지 않아요.     │
└────────────────────────────────────────────┘
```

**문구**
| 상황 | 문구 |
|---|---|
| 측정 전 | 측정이 끝나면 점수를 올릴 수 있어요. |
| 올리기 성공 | 올렸어요. 순위에 반영했어요. |
| 이미 올린 기기 | 이 기기는 마지막으로 올린 점수만 순위에 쓰여요. |
| 횟수 초과 | 잠시 후 다시 올려 주세요. 한 기기에서 1시간에 5번까지 올릴 수 있어요. |
| 연결 실패 | 점수판에 연결하지 못했어요. 잠시 후 다시 열어 주세요. |
| 설정 없음 | 섹션을 숨겨요. |
| 기록 없음 | 아직 올라온 기록이 없어요. 첫 번째로 올려 보세요. |

**개인정보 안내**
- 페이지는 IP를 따로 저장하지 않아요. 다만 Supabase 접속 기록에는 남을 수 있어요. 안내 문구에는 "이름이나 위치는 보내지 않아요"까지만 써요.
- 닉네임 칸 옆에 "실명은 쓰지 마세요"를 작게 넣어요.

**휴대폰 화면**
- 표는 `순위 · 닉네임 · 멀티`만 남기고, CPU와 싱글은 행 아래 작은 글자로 내려요.
- 가로 스크롤이 생기지 않아야 해요.

---

## 7. 일시정지 방지 (GitHub Actions)

Supabase 무료 프로젝트는 1주일 동안 DB 활동이 없으면 일시정지돼요. 3일마다 DB를 한 번 읽어서 깨워 둬요.

`.github/workflows/supabase-keepalive.yml`

```yaml
name: Supabase keep-alive

on:
  schedule:
    - cron: '0 0 */3 * *'   # 3일마다 UTC 0시 (한국 시간 9시)
  workflow_dispatch:         # Actions 탭에서 직접 실행

jobs:
  ping:
    runs-on: ubuntu-latest
    steps:
      - name: Read one row
        env:
          SUPABASE_URL: ${{ secrets.SUPABASE_URL }}
          SUPABASE_KEY: ${{ secrets.SUPABASE_KEY }}
        run: |
          curl -sf "$SUPABASE_URL/rest/v1/latest_scores?select=id&limit=1" \
            -H "apikey: $SUPABASE_KEY" -o /dev/null
          echo "ok"
```

- 저장소 **Settings → Secrets and variables → Actions**에 `SUPABASE_URL`, `SUPABASE_KEY`(공개용 키)를 넣어요.
- GitHub는 공개 저장소에서 60일 동안 커밋이 없으면 예약 실행을 멈춰요. 멈추면 메일이 오니 Actions 탭에서 다시 켜거나, 가끔 커밋하면 돼요.
- 그래도 일시정지되면 Supabase 대시보드에서 프로젝트를 다시 켜요(Restore). 데이터는 남아 있어요.

---

## 8. 설정 순서 (개인 PC에서)

1. [supabase.com](https://supabase.com)에 가입하고 **New project**를 만들어요. 지역은 **Northeast Asia (Seoul)**, 플랜은 Free.
2. **SQL Editor**에 4-1의 SQL을 붙여넣고 실행해요. 기준 기기를 넣으려면 4-2도 실행해요.
3. **Project Settings → API Keys**에서 프로젝트 URL과 공개용 키(publishable 또는 anon)를 복사해요.
4. `spec-compare.html`의 `LEADERBOARD`에 넣고, 5장과 6장대로 구현해요.
5. `build.ps1`로 다시 빌드해요.
6. GitHub 저장소에 올리고, 7장의 워크플로 파일과 Secrets를 추가해요.
7. 9장의 확인 항목을 확인해요.

---

## 9. 확인 항목

**DB 권한** (터미널에서 `curl`로 확인. `<URL>`, `<KEY>`는 3단계 값)

| 확인 | 명령 | 기대 결과 |
|---|---|---|
| 원본 표는 못 읽음 | `curl "<URL>/rest/v1/scores?select=*" -H "apikey: <KEY>"` | 401 또는 403 오류 |
| 뷰는 읽힘, device_id 없음 | `curl "<URL>/rest/v1/latest_scores?select=*" -H "apikey: <KEY>"` | 목록이 나오고 `device_id` 필드가 없음 |
| 수정 불가 | `curl -X PATCH "<URL>/rest/v1/scores?id=eq.1" -H "apikey: <KEY>" -H "Content-Type: application/json" -d "{\"multi_pts\":99999}"` | 오류, 값이 바뀌지 않음 |
| 삭제 불가 | `curl -X DELETE "<URL>/rest/v1/scores?id=eq.1" -H "apikey: <KEY>"` | 오류, 행이 그대로 |
| 범위 검사 | `multi_pts: 999999`로 POST | 400 오류 (check 제약) |
| 횟수 제한 | 같은 `device_id`로 6번 POST | 6번째에 `too many submissions` |

**페이지**
- `LEADERBOARD`를 비우면 점수판 섹션이 안 보여요.
- 측정 전에는 올리기 버튼이 꺼져 있어요.
- 올린 뒤 목록에서 내 기기 행이 강조돼요.
- 같은 기기에서 다시 올리면 목록에 한 줄만 남아요.
- 휴대폰 너비(375px)에서 가로 스크롤이 없어요.
- 아티팩트 버전에서는 "점수판에 연결하지 못했어요"만 보이고 나머지는 정상이에요.

---

## 10. 알려진 한계와 나중에 할 것

- **장난 점수:** 공개 키로 누구나 올릴 수 있어요. 많아지면 Cloudflare Turnstile 같은 사람 확인을 올리기 버튼에 붙이는 걸 고려해요.
- **브라우저 차이:** Safari(iPhone, iPad)는 엔진이 달라서 CPU 점수가 20% 정도 다르게 나올 수 있어요. 목록에 `browser`를 작게 보여주는 걸 고려해요.
- **측정 조건:** 탭이 가려지면 점수가 8~12배 낮게 나와서, 지금 코드는 화면에 보일 때만 재요. 배터리 모드, 저전력 모드, 발열도 점수를 낮춰요.
- **기준값:** `A.bench`는 앱 안 브라우저(Chromium)에서 잰 값이에요. Chrome이나 Edge에서 다시 재서 차이가 크면 바꾸고, DB의 `*_pts`는 원점수(`*_raw`)로 다시 계산해요.

### 구현과 별개로 남은 확인
- 실제 Lenovo LOQ에서 열어 보기: NVIDIA 감지, CPU 점수, "할 수 있는 것" 판단이 맞는지
- 실제 휴대폰(Android, iPhone)에서 열어 보기: 기기 감지, 측정, 레이아웃
- GitHub Pages 주소에서 WebGPU 감지(외장 그래픽 세대)가 되는지
