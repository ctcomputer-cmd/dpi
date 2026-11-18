-- DPI Department Hub - super admin rules
-- Super admin = role 'super_admin' OR role 'hod' (Head of Department).
-- Only super admins can: add staff, edit any profile, grant/remove roles,
-- change memberships and departments. Every active user can read all profiles.
-- Run in Supabase SQL Editor after 0011.

create or replace function public.is_super_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active_user()
     and (public.has_role('super_admin') or public.has_role('hod'));
$$;

-- Profiles: read stays open to all active users (0002). Update is super-admin only.
-- Users can no longer edit their own profile.
drop policy if exists profiles_self_update on public.profiles;
drop policy if exists profiles_super_admin_update on public.profiles;
create policy profiles_super_admin_update on public.profiles for update
  to authenticated
  using (public.is_super_admin())
  with check (public.is_super_admin());

-- Roles and department memberships: super admin only.
drop policy if exists user_roles_admin_write on public.user_roles;
create policy user_roles_super_admin_write on public.user_roles for all
  to authenticated
  using (public.is_super_admin())
  with check (public.is_super_admin());

drop policy if exists memberships_admin_write on public.department_memberships;
create policy memberships_super_admin_write on public.department_memberships for all
  to authenticated
  using (public.is_super_admin())
  with check (public.is_super_admin());

-- Departments: super admin only.
drop policy if exists departments_admin_write on public.departments;
create policy departments_super_admin_write on public.departments for all
  to authenticated
  using (public.is_super_admin())
  with check (public.is_super_admin());
