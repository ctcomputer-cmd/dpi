-- DPI Department Hub: sub-tasks, per-sub-task assignees, open task creation.
-- Safe to run more than once. Run after 0006.

-- 1. Any active user can create a task (the creator then manages it).
drop policy if exists tasks_create on public.tasks;
create policy tasks_create on public.tasks for insert
  to authenticated
  with check (created_by = auth.uid() and public.is_active_user());

-- 2. Sub-tasks belong to one main task
create table if not exists public.task_subtasks (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references public.tasks(id) on delete cascade,
  title text not null,
  description text,
  deadline timestamptz,
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  deleted_at timestamptz
);
create index if not exists task_subtasks_task_idx on public.task_subtasks(task_id);
alter table public.task_subtasks enable row level security;

-- 3. Who is assigned to each sub-task (one row per person per sub-task)
create table if not exists public.subtask_assignees (
  subtask_id uuid not null references public.task_subtasks(id) on delete cascade,
  user_id uuid not null references public.profiles(id),
  progress_percent int not null default 0 check (progress_percent between 0 and 100),
  status public.task_status not null default 'not_started',
  submission_note text,
  submitted_at timestamptz,
  reviewed_at timestamptz,
  reviewed_by uuid references public.profiles(id),
  review_note text,
  created_at timestamptz not null default now(),
  primary key (subtask_id, user_id)
);
alter table public.subtask_assignees enable row level security;

-- 4. Discussion messages can belong to one sub-task (null = whole-task discussion)
alter table public.task_comments
  add column if not exists subtask_id uuid references public.task_subtasks(id) on delete cascade;
create index if not exists task_comments_subtask_idx on public.task_comments(subtask_id);

-- 5. Helper functions
create or replace function public.can_see_subtask(sid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.task_subtasks s
    where s.id = sid and s.deleted_at is null and public.can_see_task(s.task_id)
  );
$$;

create or replace function public.can_manage_subtask(sid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.task_subtasks s
    where s.id = sid and public.can_manage_task(s.task_id)
  );
$$;

-- 6. Policies
drop policy if exists subtasks_read on public.task_subtasks;
create policy subtasks_read on public.task_subtasks for select to authenticated
  using (deleted_at is null and public.can_see_task(task_id));

drop policy if exists subtasks_insert on public.task_subtasks;
create policy subtasks_insert on public.task_subtasks for insert to authenticated
  with check (created_by = auth.uid() and public.can_manage_task(task_id));

drop policy if exists subtasks_update on public.task_subtasks;
create policy subtasks_update on public.task_subtasks for update to authenticated
  using (public.can_manage_task(task_id))
  with check (public.can_manage_task(task_id));

drop policy if exists sa_read on public.subtask_assignees;
create policy sa_read on public.subtask_assignees for select to authenticated
  using (public.can_see_subtask(subtask_id));

drop policy if exists sa_insert on public.subtask_assignees;
create policy sa_insert on public.subtask_assignees for insert to authenticated
  with check (public.can_manage_subtask(subtask_id));

drop policy if exists sa_delete on public.subtask_assignees;
create policy sa_delete on public.subtask_assignees for delete to authenticated
  using (public.can_manage_subtask(subtask_id));

drop policy if exists sa_update on public.subtask_assignees;
create policy sa_update on public.subtask_assignees for update to authenticated
  using (user_id = auth.uid() or public.can_manage_subtask(subtask_id))
  with check (user_id = auth.uid() or public.can_manage_subtask(subtask_id));

-- 7. Status guards
-- Main-task assignee rows are now a roll-up of sub-task rows. The roll-up writes
-- set the flag 'app.task_sync' so the guard lets them through.
create or replace function public.guard_assignee_status()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if current_setting('app.task_sync', true) = 'on' then
    return new;
  end if;
  if not public.can_manage_task(new.task_id) then
    if new.user_id <> auth.uid() then
      raise exception 'You can only update your own progress';
    end if;
    if new.status in ('completed', 'revision_required')
       and (tg_op = 'INSERT' or new.status is distinct from old.status) then
      raise exception 'Only a reviewer can set this status';
    end if;
    if tg_op = 'UPDATE' and (
         new.reviewed_at is distinct from old.reviewed_at
      or new.reviewed_by is distinct from old.reviewed_by
      or new.review_note is distinct from old.review_note) then
      raise exception 'Only a reviewer can set review fields';
    end if;
  end if;
  return new;
end $$;

create or replace function public.guard_subtask_assignee()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_task uuid;
begin
  select task_id into v_task from public.task_subtasks where id = new.subtask_id;
  if not public.can_manage_task(v_task) then
    if new.user_id <> auth.uid() then
      raise exception 'You can only update your own progress';
    end if;
    if new.status in ('completed', 'revision_required')
       and (tg_op = 'INSERT' or new.status is distinct from old.status) then
      raise exception 'Only a reviewer can set this status';
    end if;
    if tg_op = 'UPDATE' and (
         new.reviewed_at is distinct from old.reviewed_at
      or new.reviewed_by is distinct from old.reviewed_by
      or new.review_note is distinct from old.review_note) then
      raise exception 'Only a reviewer can set review fields';
    end if;
  end if;
  return new;
end $$;

drop trigger if exists guard_subtask_assignee on public.subtask_assignees;
create trigger guard_subtask_assignee before insert or update on public.subtask_assignees
  for each row execute function public.guard_subtask_assignee();

-- 8. Roll-up: keep task_assignees (one row per person per main task) in step
-- with that person's sub-task rows: average progress and a combined status.
create or replace function public.rollup_task_member(p_task uuid, p_user uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_total int;
  v_done int;
  v_review int;
  v_rev int;
  v_progress int;
  v_avg int;
  v_status public.task_status;
begin
  perform set_config('app.task_sync', 'on', true);

  select count(*),
         count(*) filter (where sa.status = 'completed'),
         count(*) filter (where sa.status = 'under_review'),
         count(*) filter (where sa.status = 'revision_required'),
         count(*) filter (where sa.progress_percent > 0),
         coalesce(round(avg(sa.progress_percent)), 0)::int
    into v_total, v_done, v_review, v_rev, v_progress, v_avg
    from public.subtask_assignees sa
    join public.task_subtasks ts on ts.id = sa.subtask_id
   where ts.task_id = p_task
     and ts.deleted_at is null
     and sa.user_id = p_user;

  if v_total = 0 then
    delete from public.task_assignees where task_id = p_task and user_id = p_user;
    return;
  end if;

  v_status := (case
    when v_done = v_total then 'completed'
    when v_rev > 0 then 'revision_required'
    when v_review > 0 then 'under_review'
    when v_progress > 0 then 'in_progress'
    else 'not_started' end)::public.task_status;

  if exists (select 1 from public.task_assignees where task_id = p_task and user_id = p_user) then
    update public.task_assignees
       set progress_percent = v_avg, status = v_status
     where task_id = p_task and user_id = p_user;
  else
    insert into public.task_assignees (task_id, user_id, progress_percent, status)
    values (p_task, p_user, v_avg, v_status);
  end if;
end $$;

create or replace function public.trg_subtask_assignee_rollup()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_task uuid;
  v_subtask uuid;
  v_user uuid;
begin
  if tg_op = 'DELETE' then
    v_subtask := old.subtask_id;
    v_user := old.user_id;
  else
    v_subtask := new.subtask_id;
    v_user := new.user_id;
  end if;

  select task_id into v_task from public.task_subtasks where id = v_subtask;
  if v_task is not null then
    perform public.rollup_task_member(v_task, v_user);
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end $$;

drop trigger if exists trg_subtask_rollup on public.subtask_assignees;
create trigger trg_subtask_rollup after insert or update or delete on public.subtask_assignees
  for each row execute function public.trg_subtask_assignee_rollup();

-- When a sub-task is removed, its people are recalculated too.
create or replace function public.trg_subtask_deleted_rollup()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  r record;
begin
  if new.deleted_at is not null and old.deleted_at is null then
    for r in select user_id from public.subtask_assignees where subtask_id = new.id loop
      perform public.rollup_task_member(new.task_id, r.user_id);
    end loop;
  end if;
  return new;
end $$;

drop trigger if exists trg_subtask_deleted on public.task_subtasks;
create trigger trg_subtask_deleted after update on public.task_subtasks
  for each row execute function public.trg_subtask_deleted_rollup();

-- 9. Notifications (run by the database)
-- Old main-task notifications would double up with the sub-task ones.
drop trigger if exists trg_notify_assignment on public.task_assignees;
drop trigger if exists trg_notify_submission on public.task_assignees;

create or replace function public.notify_subtask_assigned()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_title text;
  v_task uuid;
  v_task_title text;
  v_creator uuid;
begin
  select s.title, s.task_id into v_title, v_task from public.task_subtasks s where s.id = new.subtask_id;
  select t.title, t.created_by into v_task_title, v_creator from public.tasks t where t.id = v_task;
  if new.user_id is distinct from v_creator then
    insert into public.notifications (user_id, title, body, link)
    values (new.user_id, 'নতুন কাজ দেওয়া হয়েছে',
            coalesce(v_title, '') || ' — ' || coalesce(v_task_title, ''),
            '/tasks/' || v_task);
  end if;
  return new;
end $$;

drop trigger if exists trg_subtask_assigned on public.subtask_assignees;
create trigger trg_subtask_assigned after insert on public.subtask_assignees
  for each row execute function public.notify_subtask_assigned();

create or replace function public.notify_subtask_update()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_title text;
  v_task uuid;
  v_task_title text;
  v_creator uuid;
  v_name text;
begin
  select s.title, s.task_id into v_title, v_task from public.task_subtasks s where s.id = new.subtask_id;
  select t.title, t.created_by into v_task_title, v_creator from public.tasks t where t.id = v_task;

  -- Person submitted work -> notify the task creator
  if new.submitted_at is not null and new.submitted_at is distinct from old.submitted_at then
    select full_name into v_name from public.profiles where id = new.user_id;
    insert into public.notifications (user_id, title, body, link)
    values (v_creator, 'কাজ জমা দেওয়া হয়েছে',
            coalesce(v_name, '') || ' — ' || coalesce(v_title, ''),
            '/tasks/' || v_task);
  end if;

  -- Reviewer decided -> notify the person
  if new.reviewed_at is not null and new.reviewed_at is distinct from old.reviewed_at then
    insert into public.notifications (user_id, title, body, link)
    values (new.user_id,
            case when new.status = 'completed' then 'কাজ অনুমোদিত হয়েছে'
                 else 'কাজ সংশোধনের জন্য ফেরত এসেছে' end,
            coalesce(v_title, ''),
            '/tasks/' || v_task);
  end if;
  return new;
end $$;

drop trigger if exists trg_subtask_notify_update on public.subtask_assignees;
create trigger trg_subtask_notify_update after update on public.subtask_assignees
  for each row execute function public.notify_subtask_update();
