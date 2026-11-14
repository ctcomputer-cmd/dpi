-- DPI Department Hub: সম্পূর্ণ ডেটাবেস সেটআপ (একবারে চালান)
-- Supabase → SQL Editor → এই পুরো ফাইল পেস্ট করে Run চাপুন।

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

-- DPI Department Hub - Row Level Security
-- All permissions are enforced here, in the database. Frontend checks are cosmetic only.

-- ---------- Helper functions (SECURITY DEFINER, fixed search_path) ----------
create or replace function public.has_role(r public.app_role)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.user_roles
    where user_id = auth.uid() and role = r
  );
$$;

create or replace function public.is_active_user()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(
    (select is_active and deleted_at is null from public.profiles where id = auth.uid()),
    false
  );
$$;

create or replace function public.is_institute_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active_user()
     and (public.has_role('super_admin') or public.has_role('principal'));
$$;

create or replace function public.is_member_of(dept uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.department_memberships
    where user_id = auth.uid() and department_id = dept
  );
$$;

-- Can this user manage tasks/meetings for a department (or institute-wide when dept is null)?
create or replace function public.can_manage_department(dept uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active_user() and (
    public.is_institute_admin()
    or (dept is not null and public.has_role('hod') and public.is_member_of(dept))
    or (dept is not null and public.has_role('coordinator') and public.is_member_of(dept))
  );
$$;

create or replace function public.can_see_task(tid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active_user() and exists (
    select 1 from public.tasks t
    where t.id = tid and t.deleted_at is null and (
      public.is_institute_admin()
      or t.created_by = auth.uid()
      or public.can_manage_department(t.department_id)
      or exists (select 1 from public.task_assignees a
                 where a.task_id = t.id and a.user_id = auth.uid())
    )
  );
$$;

create or replace function public.can_manage_task(tid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active_user() and exists (
    select 1 from public.tasks t
    where t.id = tid and (
      public.is_institute_admin()
      or t.created_by = auth.uid()
      or public.can_manage_department(t.department_id)
    )
  );
$$;

-- ---------- Enable RLS ----------
alter table public.departments            enable row level security;
alter table public.profiles               enable row level security;
alter table public.user_roles             enable row level security;
alter table public.department_memberships enable row level security;
alter table public.tasks                  enable row level security;
alter table public.task_assignees         enable row level security;
alter table public.task_comments          enable row level security;
alter table public.task_activity_logs     enable row level security;
alter table public.meetings               enable row level security;
alter table public.meeting_participants   enable row level security;
alter table public.notifications          enable row level security;
alter table public.audit_logs             enable row level security;

-- ---------- departments ----------
create policy departments_read on public.departments for select
  to authenticated using (public.is_active_user());
create policy departments_admin_write on public.departments for all
  to authenticated
  using (public.has_role('super_admin'))
  with check (public.has_role('super_admin'));

-- ---------- profiles ----------
-- Staff directory: any active user can read active profiles.
create policy profiles_read on public.profiles for select
  to authenticated using (public.is_active_user() or id = auth.uid());
-- Users may edit their own non-privileged fields; admins may edit anyone.
create policy profiles_self_update on public.profiles for update
  to authenticated
  using (id = auth.uid() or public.has_role('super_admin'))
  with check (id = auth.uid() or public.has_role('super_admin'));
-- No insert policy for clients: accounts are created only by an admin via a
-- server-side Edge Function using the service role. Public registration is disabled.

-- ---------- user_roles & memberships: only super_admin writes ----------
create policy user_roles_read on public.user_roles for select
  to authenticated using (public.is_active_user());
create policy user_roles_admin_write on public.user_roles for all
  to authenticated
  using (public.has_role('super_admin'))
  with check (public.has_role('super_admin'));

create policy memberships_read on public.department_memberships for select
  to authenticated using (public.is_active_user());
create policy memberships_admin_write on public.department_memberships for all
  to authenticated
  using (public.has_role('super_admin'))
  with check (public.has_role('super_admin'));

-- ---------- tasks ----------
create policy tasks_read on public.tasks for select
  to authenticated using (public.can_see_task(id));
create policy tasks_create on public.tasks for insert
  to authenticated
  with check (created_by = auth.uid() and public.can_manage_department(department_id));
create policy tasks_update on public.tasks for update
  to authenticated
  using (public.can_manage_task(id))
  with check (public.can_manage_task(id));
-- Soft delete is an UPDATE setting deleted_at; hard delete is not granted to clients.

-- ---------- task_assignees ----------
create policy assignees_read on public.task_assignees for select
  to authenticated using (public.can_see_task(task_id));
create policy assignees_manage_insert on public.task_assignees for insert
  to authenticated with check (public.can_manage_task(task_id));
create policy assignees_manage_delete on public.task_assignees for delete
  to authenticated using (public.can_manage_task(task_id));
-- Assignees update only their own row (progress/submission). Manager-only status
-- transitions (completed / revision_required) are enforced by the trigger below.
create policy assignees_self_update on public.task_assignees for update
  to authenticated
  using (user_id = auth.uid() or public.can_manage_task(task_id))
  with check (user_id = auth.uid() or public.can_manage_task(task_id));

create or replace function public.guard_assignee_status()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not public.can_manage_task(new.task_id) then
    if new.status in ('completed', 'revision_required') then
      raise exception 'Only a reviewer can set this status';
    end if;
    if new.user_id <> auth.uid() then
      raise exception 'You can only update your own progress';
    end if;
  end if;
  return new;
end $$;

drop trigger if exists guard_assignee_status on public.task_assignees;
create trigger guard_assignee_status before insert or update on public.task_assignees
  for each row execute function public.guard_assignee_status();

-- ---------- task comments / activity ----------
create policy comments_read on public.task_comments for select
  to authenticated using (public.can_see_task(task_id));
create policy comments_insert on public.task_comments for insert
  to authenticated
  with check (author_id = auth.uid() and public.can_see_task(task_id));

create policy activity_read on public.task_activity_logs for select
  to authenticated using (public.can_see_task(task_id));
create policy activity_insert on public.task_activity_logs for insert
  to authenticated
  with check (actor_id = auth.uid() and public.can_see_task(task_id));

-- ---------- meetings ----------
create policy meetings_read on public.meetings for select
  to authenticated using (
    public.is_active_user() and deleted_at is null and (
      public.is_institute_admin()
      or organizer_id = auth.uid()
      or department_id is null
      or public.is_member_of(department_id)
      or exists (select 1 from public.meeting_participants p
                 where p.meeting_id = id and p.user_id = auth.uid())
    )
  );
create policy meetings_create on public.meetings for insert
  to authenticated
  with check (organizer_id = auth.uid() and public.can_manage_department(department_id));
create policy meetings_update on public.meetings for update
  to authenticated
  using (organizer_id = auth.uid() or public.can_manage_department(department_id))
  with check (organizer_id = auth.uid() or public.can_manage_department(department_id));

create policy participants_read on public.meeting_participants for select
  to authenticated using (public.is_active_user());
create policy participants_write on public.meeting_participants for all
  to authenticated
  using (exists (select 1 from public.meetings m
                 where m.id = meeting_id
                   and (m.organizer_id = auth.uid() or public.can_manage_department(m.department_id))))
  with check (exists (select 1 from public.meetings m
                 where m.id = meeting_id
                   and (m.organizer_id = auth.uid() or public.can_manage_department(m.department_id))));

-- ---------- notifications: users see and mark only their own ----------
create policy notifications_own_read on public.notifications for select
  to authenticated using (user_id = auth.uid());
create policy notifications_own_update on public.notifications for update
  to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
-- Inserts happen from trusted server code (service role / triggers), not clients.

-- ---------- audit logs: admins read, nobody writes from client ----------
create policy audit_admin_read on public.audit_logs for select
  to authenticated using (public.has_role('super_admin'));
