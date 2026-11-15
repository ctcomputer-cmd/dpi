-- DPI Department Hub: deadline reminders for sub-tasks.
-- Safe to run more than once. Run after 0008.
-- Needs the pg_cron extension (Supabase: Database -> Extensions -> pg_cron).

-- 1. Log of reminders already sent, so nobody gets the same reminder twice.
create table if not exists public.deadline_reminders (
  subtask_id uuid not null references public.task_subtasks(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  kind text not null check (kind in ('soon', 'overdue')),
  sent_at timestamptz not null default now(),
  primary key (subtask_id, user_id, kind)
);
-- No policies: only database functions (security definer) touch this table.
alter table public.deadline_reminders enable row level security;

-- 2. Send reminders for open sub-tasks due within 24 hours or already overdue.
create or replace function public.send_deadline_reminders()
returns integer language plpgsql security definer set search_path = public as $$
declare
  r record;
  n integer := 0;
begin
  for r in
    select sa.subtask_id,
           sa.user_id,
           s.title as subtask_title,
           t.title as task_title,
           t.id as task_id,
           case when s.deadline < now() then 'overdue' else 'soon' end as kind
      from public.subtask_assignees sa
      join public.task_subtasks s on s.id = sa.subtask_id
      join public.tasks t on t.id = s.task_id
     where s.deleted_at is null
       and t.deleted_at is null
       and t.status <> 'completed'
       and s.deadline is not null
       and s.deadline < now() + interval '24 hours'
       and sa.status not in ('completed', 'under_review')
  loop
    insert into public.deadline_reminders (subtask_id, user_id, kind)
    values (r.subtask_id, r.user_id, r.kind)
    on conflict do nothing;

    if found then
      insert into public.notifications (user_id, title, body, link)
      values (
        r.user_id,
        case when r.kind = 'overdue' then 'সময়সীমা পার হয়ে গেছে' else 'সময়সীমা কাছে' end,
        r.subtask_title || ' — ' || r.task_title,
        '/tasks/' || r.task_id
      );
      n := n + 1;
    end if;
  end loop;

  return n;
end $$;

-- 3. Run it every hour (skipped quietly if pg_cron is not enabled yet).
do $$
begin
  execute 'create extension if not exists pg_cron';
  execute $q$select cron.schedule('deadline-reminders', '0 * * * *',
                                  'select public.send_deadline_reminders();')$q$;
exception when others then
  raise notice 'pg_cron not available, enable it and re-run this migration: %', sqlerrm;
end $$;
