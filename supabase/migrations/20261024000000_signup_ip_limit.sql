-- BreakTimer: at most 3 new registrations per IP address per hour.
-- Enforced inside Supabase Auth through the "Before User Created" hook, so calling the API
-- directly with the anon key can't bypass it. Enable the hook after running this file:
-- Authentication → Hooks → Before User Created → Postgres → public.breaktimer_before_user_created.
-- IP addresses are kept for at most an hour.

-- ---------------------------------------------------------------------------
-- Sign-up attempts per IP (only Auth can read or write them)
-- ---------------------------------------------------------------------------
create table if not exists public.breaktimer_signup_attempts (
  ip inet not null,
  created_at timestamptz not null default now()
);

create index if not exists breaktimer_signup_attempts_ip_created_at_idx
  on public.breaktimer_signup_attempts (ip, created_at);

alter table public.breaktimer_signup_attempts enable row level security;

-- supabase_auth_admin doesn't bypass RLS, so the hook needs its own policy.
create policy "Auth manages sign-up attempts"
  on public.breaktimer_signup_attempts for all
  to supabase_auth_admin
  using (true)
  with check (true);

revoke all on public.breaktimer_signup_attempts from anon, authenticated, public;
grant select, insert, delete on public.breaktimer_signup_attempts to supabase_auth_admin;

-- ---------------------------------------------------------------------------
-- Before User Created hook
-- ---------------------------------------------------------------------------
-- Returns {} to allow the sign-up, or an error object that Auth turns into an HTTP 429.
-- The app matches the message "signup_ip_limit" to show its own text.
create or replace function public.breaktimer_before_user_created(event jsonb)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  client_ip inet;
  attempts integer;
begin
  begin
    client_ip := (event->'metadata'->>'ip_address')::inet;
  exception when others then
    client_ip := null;
  end;

  if client_ip is null then
    return '{}'::jsonb; -- no usable IP: never block the sign-up
  end if;

  -- Serialize sign-ups from the same IP so parallel requests can't slip past the limit.
  perform pg_advisory_xact_lock(hashtext(client_ip::text));

  delete from public.breaktimer_signup_attempts
  where created_at < now() - interval '1 hour';

  select count(*) into attempts
  from public.breaktimer_signup_attempts
  where ip = client_ip;

  if attempts >= 3 then
    return jsonb_build_object(
      'error', jsonb_build_object('http_code', 429, 'message', 'signup_ip_limit')
    );
  end if;

  insert into public.breaktimer_signup_attempts (ip) values (client_ip);
  return '{}'::jsonb;
end;
$$;

grant execute on function public.breaktimer_before_user_created(jsonb) to supabase_auth_admin;
revoke execute on function public.breaktimer_before_user_created(jsonb) from authenticated, anon, public;
