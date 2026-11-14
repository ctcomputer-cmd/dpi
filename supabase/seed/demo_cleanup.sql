-- DPI Department Hub: remove ALL demo rows (anything titled/named with [DEMO]).
-- Real data is not touched. Run in Supabase → SQL Editor.

do $$
begin
  delete from public.task_comments
    where task_id in (select id from public.tasks where title like '[DEMO]%');
  delete from public.task_assignees
    where task_id in (select id from public.tasks where title like '[DEMO]%');
  delete from public.tasks where title like '[DEMO]%';

  delete from public.meeting_participants
    where meeting_id in (select id from public.meetings where title like '[DEMO]%');
  delete from public.meetings where title like '[DEMO]%';

  delete from public.notifications where title like '[DEMO]%';

  delete from public.departments where code like 'DEMO-%';
end $$;
