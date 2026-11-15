-- DPI Department Hub: push tokens per phone. Safe to run more than once.
-- Run after 0009.

create table if not exists public.device_tokens (
  token text primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  platform text not null default 'android',
  updated_at timestamptz not null default now()
);

alter table public.device_tokens enable row level security;

-- Each user manages only their own phone tokens. Sending uses the server side.
drop policy if exists device_tokens_own on public.device_tokens;
create policy device_tokens_own on public.device_tokens for all
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
