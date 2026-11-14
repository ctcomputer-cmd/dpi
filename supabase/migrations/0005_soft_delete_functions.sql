-- DPI Department Hub: reliable soft delete for tasks and meetings.
-- The function checks the caller's permission itself, then marks the row deleted.
-- Safe to run more than once.

create or replace function public.soft_delete_task(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.can_manage_task(p_id) then
    raise exception 'You are not allowed to delete this task';
  end if;
  update public.tasks
     set deleted_at = now(), updated_by = auth.uid()
   where id = p_id and deleted_at is null;
end $$;

create or replace function public.soft_delete_meeting(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_org uuid;
  v_dept uuid;
begin
  select organizer_id, department_id into v_org, v_dept
  from public.meetings where id = p_id and deleted_at is null;
  if v_org is null then
    raise exception 'Meeting not found';
  end if;
  if v_org <> auth.uid() and not public.can_manage_department(v_dept) then
    raise exception 'You are not allowed to delete this meeting';
  end if;
  update public.meetings set deleted_at = now() where id = p_id;
end $$;

revoke execute on function public.soft_delete_task(uuid) from public;
revoke execute on function public.soft_delete_meeting(uuid) from public;
grant execute on function public.soft_delete_task(uuid) to authenticated;
grant execute on function public.soft_delete_meeting(uuid) to authenticated;
