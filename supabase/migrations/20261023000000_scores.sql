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

revoke all on public.scores from anon, authenticated;
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

revoke all on public.latest_scores from anon, authenticated;
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

-- 트리거로만 쓰는 함수라 직접 실행 권한은 막아 둬요
revoke execute on function public.limit_score_inserts() from public, anon, authenticated;

create trigger scores_rate_limit
  before insert on public.scores
  for each row execute function public.limit_score_inserts();
