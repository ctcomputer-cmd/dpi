-- DPI Department Hub: fix "new row violates row-level security policy for table tasks".
-- Cause: tasks_read called can_see_task(id), which re-queries the tasks table.
-- A newly inserted row is not visible to that query inside the same statement,
-- so the INSERT ... RETURNING check failed. This version checks the row's own
-- columns directly. Safe to run more than once.

-- Assignee check against a different table (SECURITY DEFINER bypasses RLS).
create or replace function public.is_task_assignee(tid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.task_assignees
    where task_id = tid and user_id = auth.uid()
  );
$$;

drop policy if exists tasks_read on public.tasks;
create policy tasks_read on public.tasks for select
  to authenticated using (
    public.is_active_user() and deleted_at is null and (
      public.is_institute_admin()
      or created_by = auth.uid()
      or public.can_manage_department(department_id)
      or public.is_task_assignee(id)
    )
  );
