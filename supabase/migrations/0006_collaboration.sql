-- DPI Department Hub: task workflow, attachments, notifications.
-- Safe to run more than once.

-- 1. Submission / review fields on each teacher's assignment row
alter table public.task_assignees add column if not exists submitted_at timestamptz;
alter table public.task_assignees add column if not exists reviewed_at timestamptz;
alter table public.task_assignees add column if not exists reviewed_by uuid references public.profiles(id);
alter table public.task_assignees add column if not exists review_note text;

-- Assignees may not set review fields; only managers may (guard extended).
create or replace function public.guard_assignee_status()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not public.can_manage_task(new.task_id) then
    if new.user_id <> auth.uid() then
      raise exception 'You can only update your own progress';
    end if;
    if new.status in ('completed', 'revision_required') then
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

-- 2. Attachments
create table if not exists public.task_attachments (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references public.tasks(id) on delete cascade,
  uploaded_by uuid not null references public.profiles(id),
  file_name text not null,
  storage_path text not null unique,
  mime_type text,
  size_bytes bigint check (size_bytes is null or size_bytes <= 10485760),
  created_at timestamptz not null default now()
);
alter table public.task_attachments enable row level security;

drop policy if exists attachments_read on public.task_attachments;
create policy attachments_read on public.task_attachments for select
  to authenticated using (public.can_see_task(task_id));

drop policy if exists attachments_insert on public.task_attachments;
create policy attachments_insert on public.task_attachments for insert
  to authenticated with check (uploaded_by = auth.uid() and public.can_see_task(task_id));

drop policy if exists attachments_delete on public.task_attachments;
create policy attachments_delete on public.task_attachments for delete
  to authenticated using (uploaded_by = auth.uid() or public.can_manage_task(task_id));

-- Private storage bucket for task files (max 10 MB, enforced by the app and the table)
insert into storage.buckets (id, name, public, file_size_limit)
values ('task-files', 'task-files', false, 10485760)
on conflict (id) do nothing;

drop policy if exists task_files_read on storage.objects;
create policy task_files_read on storage.objects for select to authenticated
  using (bucket_id = 'task-files'
         and public.can_see_task(((storage.foldername(name))[1])::uuid));

drop policy if exists task_files_insert on storage.objects;
create policy task_files_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'task-files'
         and public.can_see_task(((storage.foldername(name))[1])::uuid));

drop policy if exists task_files_delete on storage.objects;
create policy task_files_delete on storage.objects for delete to authenticated
  using (bucket_id = 'task-files'
         and public.can_manage_task(((storage.foldername(name))[1])::uuid));

-- 3. Automatic in-app notifications (run by the database, not by the client)
create or replace function public.notify_assignment()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_title text;
begin
  select title into v_title from public.tasks where id = new.task_id;
  insert into public.notifications (user_id, title, body, link)
  values (new.user_id, 'নতুন কাজ দেওয়া হয়েছে', v_title, '/tasks/' || new.task_id);
  return new;
end $$;

drop trigger if exists trg_notify_assignment on public.task_assignees;
create trigger trg_notify_assignment after insert on public.task_assignees
  for each row execute function public.notify_assignment();

create or replace function public.notify_submission_or_review()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_title text;
  v_creator uuid;
  v_name text;
begin
  select title, created_by into v_title, v_creator from public.tasks where id = new.task_id;

  -- Teacher submitted work -> notify the task creator
  if new.submitted_at is not null and new.submitted_at is distinct from old.submitted_at then
    select full_name into v_name from public.profiles where id = new.user_id;
    insert into public.notifications (user_id, title, body, link)
    values (v_creator, 'কাজ জমা দেওয়া হয়েছে',
            coalesce(v_name, '') || ' — ' || coalesce(v_title, ''),
            '/tasks/' || new.task_id);
  end if;

  -- Reviewer decided -> notify the teacher
  if new.reviewed_at is not null and new.reviewed_at is distinct from old.reviewed_at then
    insert into public.notifications (user_id, title, body, link)
    values (new.user_id,
            case when new.status = 'completed' then 'কাজ অনুমোদিত হয়েছে'
                 else 'কাজ সংশোধনের জন্য ফেরত এসেছে' end,
            coalesce(v_title, ''),
            '/tasks/' || new.task_id);
  end if;
  return new;
end $$;

drop trigger if exists trg_notify_submission on public.task_assignees;
create trigger trg_notify_submission after update on public.task_assignees
  for each row execute function public.notify_submission_or_review();

create or replace function public.notify_meeting_invite()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_title text;
begin
  select title into v_title from public.meetings where id = new.meeting_id;
  insert into public.notifications (user_id, title, body, link)
  values (new.user_id, 'সভার আমন্ত্রণ', v_title, '/meetings');
  return new;
end $$;

drop trigger if exists trg_notify_meeting on public.meeting_participants;
create trigger trg_notify_meeting after insert on public.meeting_participants
  for each row execute function public.notify_meeting_invite();
