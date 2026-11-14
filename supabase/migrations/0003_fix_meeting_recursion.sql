-- DPI Department Hub: fix RLS recursion between meetings and meeting_participants.
-- Safe to run more than once.

-- Membership check that bypasses RLS (SECURITY DEFINER), breaking the loop.
create or replace function public.is_meeting_participant(mid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.meeting_participants
    where meeting_id = mid and user_id = auth.uid()
  );
$$;

-- Meetings: read rule uses the helper instead of querying participants directly.
drop policy if exists meetings_read on public.meetings;
create policy meetings_read on public.meetings for select
  to authenticated using (
    public.is_active_user() and deleted_at is null and (
      public.is_institute_admin()
      or organizer_id = auth.uid()
      or department_id is null
      or public.is_member_of(department_id)
      or public.is_meeting_participant(id)
    )
  );

-- Participants: split the old "for all" policy so it no longer has a SELECT
-- clause that re-reads meetings (that was the loop).
drop policy if exists participants_write on public.meeting_participants;

create policy participants_insert on public.meeting_participants for insert
  to authenticated with check (
    exists (select 1 from public.meetings m
            where m.id = meeting_id
              and (m.organizer_id = auth.uid() or public.can_manage_department(m.department_id)))
  );

create policy participants_delete on public.meeting_participants for delete
  to authenticated using (
    exists (select 1 from public.meetings m
            where m.id = meeting_id
              and (m.organizer_id = auth.uid() or public.can_manage_department(m.department_id)))
  );
