-- ============================================================================
--  Energy Duels - group report backend
--  Run in the Supabase SQL editor: Dashboard > SQL Editor > New query
-- ============================================================================
--  HOW TO RUN
--    Open this file in a text editor, select ALL of it (Ctrl+A), copy, paste
--    into the SQL editor, and click Run.
--
--    If it errors, the paste was probably truncated. Run the four PARTs below
--    one at a time instead - each is self-contained and safe to re-run.
--    PART 4 tells you whether everything landed.
-- ============================================================================
--  DESIGN
--    * Stores four scores, an optional tie-break winner, an optional pressure
--      tendency. No names, no free text, no individual answers.
--    * RLS is on and there are NO policies, so the public anon key cannot
--      read, insert, update or delete rows directly.
--    * All access goes through two SECURITY DEFINER functions, which validate
--      their inputs and enforce the n>=5 anonymity gate inside the database.
-- ============================================================================


-- ============================================================================
--  PART 1 of 4  -  table
-- ============================================================================

create extension if not exists pgcrypto;

create table if not exists public.duel_results (
  id              uuid primary key default gen_random_uuid(),
  room_code       text        not null check (room_code ~ '^[A-HJKMNP-Z2-9]{6}$'),
  client_id       text        not null check (length(client_id) between 8 and 64),
  sov             smallint    not null check (sov between 0 and 12),
  war             smallint    not null check (war between 0 and 12),
  lov             smallint    not null check (lov between 0 and 12),
  jes             smallint    not null check (jes between 0 and 12),
  tiebreak_winner text        check (tiebreak_winner in ('SOV','WAR','LOV','JES')),
  pressure        text        check (pressure in ('P_SOV','P_WAR','P_LOV','P_JES','P_SKIP')),
  created_at      timestamptz not null default now(),
  constraint duel_results_total_12 check (sov + war + lov + jes = 12),
  constraint duel_results_one_per_device unique (room_code, client_id)
);

create index if not exists duel_results_room_idx
  on public.duel_results (room_code, created_at);

-- Lock the table down. No policies are created, so RLS denies everything.
alter table public.duel_results enable row level security;
revoke all on public.duel_results from anon, authenticated;


-- ============================================================================
--  PART 2 of 4  -  submit function
--  Must end with the line:   $duel_submit$;
-- ============================================================================

create or replace function public.duel_submit(
  p_code     text,
  p_client   text,
  p_sov      int,
  p_war      int,
  p_lov      int,
  p_jes      int,
  p_tiebreak text default null,
  p_pressure text default null
) returns void
language plpgsql
security definer
set search_path = public
as $duel_submit$
declare
  v_code text := upper(btrim(p_code));
  v_n    int;
begin
  if v_code !~ '^[A-HJKMNP-Z2-9]{6}$' then
    raise exception 'invalid workshop code';
  end if;

  if coalesce(p_sov,0) + coalesce(p_war,0) + coalesce(p_lov,0) + coalesce(p_jes,0) <> 12 then
    raise exception 'scores must total 12';
  end if;

  -- Cheap flood guard: a workshop is people in a room, not a firehose.
  select count(*) into v_n from duel_results where room_code = v_code;
  if v_n >= 500 then
    raise exception 'workshop is full';
  end if;

  insert into duel_results
    (room_code, client_id, sov, war, lov, jes, tiebreak_winner, pressure)
  values
    (v_code, p_client, p_sov, p_war, p_lov, p_jes,
     nullif(p_tiebreak,''), nullif(p_pressure,''))
  on conflict (room_code, client_id) do update set
    sov             = excluded.sov,
    war             = excluded.war,
    lov             = excluded.lov,
    jes             = excluded.jes,
    tiebreak_winner = excluded.tiebreak_winner,
    pressure        = excluded.pressure,
    created_at      = now();
end;
$duel_submit$;


-- ============================================================================
--  PART 3 of 4  -  report function and grants
--  Must end with the four grant/revoke lines.
-- ============================================================================

-- Returns {n, locked:true} until five people have finished, so an individual
-- result can never be pulled out of a small room.
create or replace function public.duel_room_report(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $duel_report$
declare
  v_code text := upper(btrim(p_code));
  v_n    int;
  v_rows jsonb;
begin
  if v_code !~ '^[A-HJKMNP-Z2-9]{6}$' then
    return jsonb_build_object('n', 0, 'locked', true);
  end if;

  select count(*) into v_n from duel_results where room_code = v_code;

  if v_n < 5 then
    return jsonb_build_object('n', v_n, 'locked', true);
  end if;

  select jsonb_agg(
           jsonb_build_object(
             'SOV', sov, 'WAR', war, 'LOV', lov, 'JES', jes,
             'tb', tiebreak_winner, 'pressure', pressure
           ) order by created_at
         )
    into v_rows
    from duel_results
   where room_code = v_code;

  return jsonb_build_object('n', v_n, 'locked', false, 'rows', coalesce(v_rows, '[]'::jsonb));
end;
$duel_report$;

revoke all on function public.duel_submit(text,text,int,int,int,int,text,text) from public;
revoke all on function public.duel_room_report(text)                           from public;
grant execute on function public.duel_submit(text,text,int,int,int,int,text,text) to anon, authenticated;
grant execute on function public.duel_room_report(text)                           to anon, authenticated;


-- ============================================================================
--  PART 4 of 4  -  check it worked
--  Expect exactly three rows, all saying OK.
-- ============================================================================

select 'table duel_results' as object,
       case when to_regclass('public.duel_results') is not null
            then 'OK' else 'MISSING - rerun PART 1' end as status
union all
select 'function duel_submit',
       case when exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                         where n.nspname = 'public' and p.proname = 'duel_submit')
            then 'OK' else 'MISSING - rerun PART 2' end
union all
select 'function duel_room_report',
       case when exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                         where n.nspname = 'public' and p.proname = 'duel_room_report')
            then 'OK' else 'MISSING - rerun PART 3' end;


-- ============================================================================
--  Optional housekeeping - run by hand, or schedule with pg_cron.
--    delete from public.duel_results where created_at < now() - interval '90 days';
-- ============================================================================
