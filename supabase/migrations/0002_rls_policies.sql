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
