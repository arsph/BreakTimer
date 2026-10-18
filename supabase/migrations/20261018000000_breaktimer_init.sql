-- BreakTimer: break sessions and per-user settings.
-- Every user can only read and write their own rows (RLS). Rows are never hard-deleted by the
-- app: deletes are soft (deleted_at) so they sync to other devices. Account deletion removes
-- everything through ON DELETE CASCADE from auth.users.

-- ---------------------------------------------------------------------------
-- updated_at: maintained by trigger, "latest updated_at wins"
-- ---------------------------------------------------------------------------
-- Clients send the updated_at of their local change (UTC). The trigger
--   * fills in now() when no updated_at is given,
--   * ignores an update whose updated_at is older than the stored one, so a stale device
--     can never overwrite a newer change (last-writer-wins, decided atomically on the server).
create or replace function public.breaktimer_set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.updated_at is null then
    new.updated_at := now();
  end if;

  if tg_op = 'UPDATE' and new.updated_at < old.updated_at then
    return old; -- stale write: keep the newer row
  end if;

  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- break_sessions
-- ---------------------------------------------------------------------------
create table public.break_sessions (
  id             uuid primary key,                       -- generated on the device
  user_id        uuid not null default auth.uid()
                   references auth.users (id) on delete cascade,
  started_at     timestamptz not null,
  ended_at       timestamptz,                            -- null while the break runs
  day            date not null,                          -- local calendar date of started_at
  budget_minutes int not null check (budget_minutes between 10 and 120),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  deleted_at     timestamptz,                            -- soft delete for sync
  constraint break_sessions_end_after_start check (ended_at is null or ended_at >= started_at)
);

create index break_sessions_user_day_idx on public.break_sessions (user_id, day);

create trigger break_sessions_set_updated_at
  before insert or update on public.break_sessions
  for each row execute function public.breaktimer_set_updated_at();

alter table public.break_sessions enable row level security;

create policy "Users can read their own sessions"
  on public.break_sessions for select
  to authenticated
  using (user_id = (select auth.uid()));

create policy "Users can insert their own sessions"
  on public.break_sessions for insert
  to authenticated
  with check (user_id = (select auth.uid()));

create policy "Users can update their own sessions"
  on public.break_sessions for update
  to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- ---------------------------------------------------------------------------
-- user_settings
-- ---------------------------------------------------------------------------
create table public.user_settings (
  user_id              uuid primary key default auth.uid()
                         references auth.users (id) on delete cascade,
  daily_budget_minutes int not null default 30 check (daily_budget_minutes between 10 and 120),
  updated_at           timestamptz not null default now()
);

create trigger user_settings_set_updated_at
  before insert or update on public.user_settings
  for each row execute function public.breaktimer_set_updated_at();

alter table public.user_settings enable row level security;

create policy "Users can read their own settings"
  on public.user_settings for select
  to authenticated
  using (user_id = (select auth.uid()));

create policy "Users can insert their own settings"
  on public.user_settings for insert
  to authenticated
  with check (user_id = (select auth.uid()));

create policy "Users can update their own settings"
  on public.user_settings for update
  to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- ---------------------------------------------------------------------------
-- Privileges: signed-in users only, no hard deletes from the API.
-- ---------------------------------------------------------------------------
revoke all on public.break_sessions from anon;
revoke all on public.user_settings from anon;
revoke delete, truncate on public.break_sessions from authenticated;
revoke delete, truncate on public.user_settings from authenticated;
grant select, insert, update on public.break_sessions to authenticated;
grant select, insert, update on public.user_settings to authenticated;
