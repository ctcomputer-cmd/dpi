-- DPI Department Hub: one overall progress number per task, kept by the database.
-- Dashboard and task details show the same value. Safe to run more than once.
-- Run after 0010.

alter table public.tasks
  add column if not exists progress_percent int not null default 0
  check (progress_percent between 0 and 100);

-- Average progress of every assignment on the task's open sub-tasks.
create or replace function public.recalc_task_progress(p_task uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.tasks t
     set progress_percent = coalesce((
           select round(avg(sa.progress_percent))::int
             from public.subtask_assignees sa
             join public.task_subtasks ts on ts.id = sa.subtask_id
            where ts.task_id = p_task and ts.deleted_at is null
         ), 0)
   where t.id = p_task;
end $$;

create or replace function public.trg_task_progress_from_assignee()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_sub uuid;
  v_task uuid;
begin
  if tg_op = 'DELETE' then v_sub := old.subtask_id; else v_sub := new.subtask_id; end if;
  select task_id into v_task from public.task_subtasks where id = v_sub;
  if v_task is not null then
    perform public.recalc_task_progress(v_task);
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end $$;

drop trigger if exists trg_task_progress_sa on public.subtask_assignees;
create trigger trg_task_progress_sa after insert or update or delete on public.subtask_assignees
  for each row execute function public.trg_task_progress_from_assignee();

create or replace function public.trg_task_progress_from_subtask()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.deleted_at is not null and old.deleted_at is null then
    perform public.recalc_task_progress(new.task_id);
  end if;
  return new;
end $$;

drop trigger if exists trg_task_progress_sub on public.task_subtasks;
create trigger trg_task_progress_sub after update on public.task_subtasks
  for each row execute function public.trg_task_progress_from_subtask();

-- Fill in the value for tasks that already exist.
do $$
declare r record;
begin
  for r in select id from public.tasks loop
    perform public.recalc_task_progress(r.id);
  end loop;
end $$;
