-- DPI Department Hub: tighter visibility for sub-tasks, reopen on revision,
-- notify on new discussion messages. Safe to run more than once. Run after 0007.

-- 1. Is this user assigned to the sub-task?
create or replace function public.is_subtask_member(sid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.subtask_assignees sa
    where sa.subtask_id = sid and sa.user_id = auth.uid()
  );
$$;

-- 2. Sub-tasks: managers see all; an assignee sees only the sub-tasks they hold.
create or replace function public.can_see_subtask(sid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.task_subtasks s
    where s.id = sid and s.deleted_at is null
      and (public.can_manage_task(s.task_id) or public.is_subtask_member(s.id))
  );
$$;

drop policy if exists subtasks_read on public.task_subtasks;
create policy subtasks_read on public.task_subtasks for select to authenticated
  using (deleted_at is null and (public.can_manage_task(task_id) or public.is_subtask_member(id)));

-- 3. People on a sub-task: managers see everyone; others see only their own row.
drop policy if exists sa_read on public.subtask_assignees;
create policy sa_read on public.subtask_assignees for select to authenticated
  using (user_id = auth.uid() or public.can_manage_subtask(subtask_id));

-- 4. Activity log: managers only (it names other people and other sub-tasks).
drop policy if exists activity_read on public.task_activity_logs;
create policy activity_read on public.task_activity_logs for select
  to authenticated using (public.can_manage_task(task_id));

-- 5. Discussion: whole-task thread is open to the task's people;
-- a sub-task thread is open only to its assignees and managers.
drop policy if exists comments_read on public.task_comments;
create policy comments_read on public.task_comments for select to authenticated
  using (
    (subtask_id is null and public.can_see_task(task_id))
    or (subtask_id is not null and (
          public.can_manage_subtask(subtask_id) or public.is_subtask_member(subtask_id)))
  );

drop policy if exists comments_insert on public.task_comments;
create policy comments_insert on public.task_comments for insert to authenticated
  with check (
    author_id = auth.uid() and (
      (subtask_id is null and public.can_see_task(task_id))
      or (subtask_id is not null and (
            public.can_manage_subtask(subtask_id) or public.is_subtask_member(subtask_id)))
    )
  );

-- 6. If a sub-task goes back for revision, a completed main task is open again.
create or replace function public.trg_reopen_task_on_revision()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'revision_required' and new.status is distinct from old.status then
    update public.tasks
       set status = 'in_progress'
     where status = 'completed'
       and id = (select task_id from public.task_subtasks where id = new.subtask_id);
  end if;
  return new;
end $$;

drop trigger if exists trg_reopen_on_revision on public.subtask_assignees;
create trigger trg_reopen_on_revision after update on public.subtask_assignees
  for each row execute function public.trg_reopen_task_on_revision();

-- 7. Notify people when a new discussion message is posted (not the author).
create or replace function public.notify_new_comment()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_title text;
  v_creator uuid;
begin
  select title, created_by into v_title, v_creator from public.tasks where id = new.task_id;

  insert into public.notifications (user_id, title, body, link)
  select distinct r.uid,
         'নতুন আলোচনা',
         left(coalesce(v_title, '') || ': ' || new.body, 200),
         '/tasks/' || new.task_id
    from (
      select v_creator as uid
      union
      select sa.user_id
        from public.subtask_assignees sa
       where new.subtask_id is not null and sa.subtask_id = new.subtask_id
      union
      select ta.user_id
        from public.task_assignees ta
       where new.subtask_id is null and ta.task_id = new.task_id
    ) r
   where r.uid is not null and r.uid <> new.author_id;

  return new;
end $$;

drop trigger if exists trg_notify_new_comment on public.task_comments;
create trigger trg_notify_new_comment after insert on public.task_comments
  for each row execute function public.notify_new_comment();
