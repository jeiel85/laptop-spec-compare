-- keep-alive 핑 기록. 읽기 전용 핑만으로는 무료 프로젝트 일시정지를 막지 못해서(2026-10-31 정지)
-- 핑할 때마다 한 줄짜리 행을 실제로 갱신해요
create table public.keepalive (
  id        smallint primary key default 1 check (id = 1),  -- 행은 하나만 둬요
  pinged_at timestamptz not null default now(),
  pings     bigint not null default 0
);

insert into public.keepalive (id) values (1);

-- 테이블은 직접 못 건드리고 아래 함수로만 갱신해요
alter table public.keepalive enable row level security;
revoke all on public.keepalive from anon, authenticated;

-- 누가 불러도 행 하나의 시각만 바뀌니 공개 키로 불러도 괜찮아요
create or replace function public.keepalive_ping()
returns timestamptz
language sql
security definer
set search_path = public
as $$
  update public.keepalive
     set pinged_at = now(), pings = pings + 1
   where id = 1
  returning pinged_at;
$$;

revoke execute on function public.keepalive_ping() from public, authenticated;
grant execute on function public.keepalive_ping() to anon;
