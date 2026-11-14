-- DPI Department Hub: DEMO DATA ONLY
-- Every row is marked with "[DEMO]" so it can be removed with demo_cleanup.sql.
-- Run AFTER 0001 + 0002 migrations and after creating the first super admin
-- (docs/SETUP.md, step 4). Run in Supabase → SQL Editor.

do $$
declare
  v_admin uuid;
  v_cst   uuid;
  v_eee   uuid;
  v_task  uuid;
begin
  select p.id into v_admin
  from public.profiles p
  join public.user_roles r on r.user_id = p.id and r.role = 'super_admin'
  limit 1;

  if v_admin is null then
    raise exception 'No super admin found. Create the admin first (docs/SETUP.md, step 4).';
  end if;

  -- Departments
  insert into public.departments (name, code) values
    ('[DEMO] Computer Science & Technology', 'DEMO-CST'),
    ('[DEMO] Electrical & Electronic Engineering', 'DEMO-EEE')
  on conflict (code) do nothing;

  select id into v_cst from public.departments where code = 'DEMO-CST';
  select id into v_eee from public.departments where code = 'DEMO-EEE';

  -- Tasks (created_by = admin; assignee = admin)
  insert into public.tasks (title, description, category, department_id, priority, status, start_date, deadline, created_by)
  values (
    '[DEMO] Prepare semester course outline',
    'Draft the course outline for the next semester and share it with the department.',
    'Academic', v_cst, 'high', 'in_progress',
    current_date - 10, now() + interval '3 days', v_admin
  ) returning id into v_task;
  insert into public.task_assignees (task_id, user_id, progress_percent, status)
  values (v_task, v_admin, 60, 'in_progress');
  insert into public.task_comments (task_id, author_id, body)
  values (v_task, v_admin, '[DEMO] Outline draft is 60% complete.');

  insert into public.tasks (title, description, category, department_id, priority, status, start_date, deadline, created_by)
  values (
    '[DEMO] Lab equipment inventory check',
    'Verify all computers and equipment in Lab 1 and report issues.',
    'Laboratory', v_cst, 'urgent', 'not_started',
    current_date - 2, now() - interval '2 days', v_admin
  ) returning id into v_task;
  insert into public.task_assignees (task_id, user_id, progress_percent, status)
  values (v_task, v_admin, 0, 'not_started');

  insert into public.tasks (title, description, category, department_id, priority, status, start_date, deadline, created_by)
  values (
    '[DEMO] Annual sports event planning',
    'Plan venues, schedules and volunteers for the annual sports event.',
    'Event', v_eee, 'medium', 'under_review',
    current_date - 20, now() + interval '10 days', v_admin
  ) returning id into v_task;
  insert into public.task_assignees (task_id, user_id, progress_percent, status)
  values (v_task, v_admin, 90, 'under_review');

  insert into public.tasks (title, description, category, department_id, priority, status, start_date, deadline, created_by)
  values (
    '[DEMO] Institute-wide: update staff contact information',
    'Every staff member must update their phone number and email in the profile.',
    'Administration', null, 'low', 'not_started',
    current_date, now() + interval '14 days', v_admin
  );

  -- Meetings
  insert into public.meetings (title, agenda, description, department_id, organizer_id, starts_at, ends_at, meet_link, status)
  values (
    '[DEMO] CST department weekly meeting',
    '1. Results review  2. Upcoming exams  3. AOB',
    'Regular weekly coordination meeting.',
    v_cst, v_admin,
    now() + interval '1 day', now() + interval '1 day' + interval '90 minutes',
    'https://meet.google.com/demo-xxxx-xxx', 'scheduled'
  );

  insert into public.meetings (title, agenda, description, department_id, organizer_id, starts_at, ends_at, meet_link, status)
  values (
    '[DEMO] Institute-wide orientation',
    'Introduction of new digital systems.',
    'Open to all staff.',
    null, v_admin,
    now() + interval '5 days', now() + interval '5 days' + interval '60 minutes',
    null, 'scheduled'
  );

  -- Notifications for the admin
  insert into public.notifications (user_id, title, body, is_read) values
    (v_admin, '[DEMO] Task overdue', 'Lab equipment inventory check is past its deadline.', false),
    (v_admin, '[DEMO] Meeting reminder', 'CST department weekly meeting starts tomorrow.', false),
    (v_admin, '[DEMO] Welcome', 'Your DPI Department Hub account is ready.', true);
end $$;
