-- DPI Department Hub - core schema (Phase 1 MVP)
-- Run in Supabase SQL editor in order. Requires Supabase Auth (auth.users).

create extension if not exists "pgcrypto";

-- ---------- Organisation & departments ----------
create table if not exists public.departments (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  code text not null unique,
  created_at timestamptz not null default now(),
  deleted_at timestamptz
);

-- ---------- Profiles (one per auth user) ----------
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  employee_id text unique,
  designation text,
  email text not null,
  phone text,
  joining_date date,
  bio text,
  is_active boolean not null default true,
  created_by uuid references public.profiles(id),
  updated_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

-- ---------- Roles ----------
do $$ begin
  create type public.app_role as enum (
    'super_admin', 'principal', 'hod', 'coordinator',
    'teacher', 'lab_incharge', 'event_coordinator'
  );
exception when duplicate_object then null; end $$;

create table if not exists public.user_roles (
  user_id uuid not null references public.profiles(id) on delete cascade,
  role public.app_role not null,
  primary key (user_id, role)
);

create table if not exists public.department_memberships (
  user_id uuid not null references public.profiles(id) on delete cascade,
  department_id uuid not null references public.departments(id) on delete cascade,
  primary key (user_id, department_id)
);

-- ---------- Tasks ----------
do $$ begin
  create type public.task_priority as enum ('low', 'medium', 'high', 'urgent');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.task_status as enum (
    'not_started', 'in_progress', 'under_review',
    'revision_required', 'completed', 'cancelled'
  );
exception when duplicate_object then null; end $$;

create table if not exists public.tasks (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(title) between 1 and 200),
  description text,
  category text,
  department_id uuid references public.departments(id), -- null = institute-wide
  priority public.task_priority not null default 'medium',
  status public.task_status not null default 'not_started',
  start_date date,
  deadline timestamptz,
  created_by uuid not null references public.profiles(id),
  updated_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create index if not exists tasks_department_idx on public.tasks(department_id);
create index if not exists tasks_deadline_idx on public.tasks(deadline);

-- Individual progress per assignee (each teacher separately)
create table if not exists public.task_assignees (
  task_id uuid not null references public.tasks(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  progress_percent smallint not null default 0 check (progress_percent between 0 and 100),
  status public.task_status not null default 'not_started',
  submission_note text,
  updated_at timestamptz not null default now(),
  primary key (task_id, user_id)
);

create table if not exists public.task_comments (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references public.tasks(id) on delete cascade,
  author_id uuid not null references public.profiles(id),
  body text not null check (char_length(body) between 1 and 4000),
  created_at timestamptz not null default now()
);

create table if not exists public.task_activity_logs (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references public.tasks(id) on delete cascade,
  actor_id uuid references public.profiles(id),
  action text not null,
  details jsonb,
  created_at timestamptz not null default now()
);

-- ---------- Meetings ----------
create table if not exists public.meetings (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(title) between 1 and 200),
  agenda text,
  description text,
  department_id uuid references public.departments(id), -- null = institute-wide
  organizer_id uuid not null references public.profiles(id),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  meet_link text,                       -- entered manually (fallback)
  status text not null default 'scheduled' check (status in ('scheduled','ongoing','completed','cancelled')),
  notes text,
  decisions text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  check (ends_at > starts_at)
);

create table if not exists public.meeting_participants (
  meeting_id uuid not null references public.meetings(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  primary key (meeting_id, user_id)
);

-- ---------- Notifications ----------
create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  body text,
  link text,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists notifications_user_idx on public.notifications(user_id, is_read);

-- ---------- Audit ----------
create table if not exists public.audit_logs (
  id bigserial primary key,
  actor_id uuid references public.profiles(id),
  action text not null,
  target_table text,
  target_id uuid,
  details jsonb,
  created_at timestamptz not null default now()
);

-- ---------- updated_at trigger ----------
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

drop trigger if exists profiles_updated on public.profiles;
create trigger profiles_updated before update on public.profiles
  for each row execute function public.set_updated_at();
drop trigger if exists tasks_updated on public.tasks;
create trigger tasks_updated before update on public.tasks
  for each row execute function public.set_updated_at();
drop trigger if exists meetings_updated on public.meetings;
create trigger meetings_updated before update on public.meetings
  for each row execute function public.set_updated_at();
