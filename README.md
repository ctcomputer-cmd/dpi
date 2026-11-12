# DPI Department Hub

Android app for Daffodil Polytechnic Institute, Department of Computer Science and Technology.
Built with Flutter, Riverpod, GoRouter and Supabase (PostgreSQL, Auth, Row Level Security).

## Status

This is the **Phase 1 MVP foundation**. See the list below for what is complete and what is not.

### Working in code
- Login (email + password). Public sign-up is disabled.
- Role-based database security (RLS) for departments, staff, roles, tasks, assignees, comments, meetings, notifications and audit logs.
- Bottom navigation: Home, Tasks, Meetings, Alerts, Profile.
- Dashboard with live counts: teachers, active tasks, completed, overdue.
- Task list with status, priority and deadline (overdue shown in red).
- Meeting list with manual Google Meet links (opens in browser).
- Notification list with mark-as-read.
- Staff directory with search.
- Profile view and sign-out.
- Loading, empty, error and retry states.
- Bangla and English locales declared (text translations are partial).

### Not yet built
- Creating and editing teachers (needs a server-side Edge Function for account creation).
- Creating and editing tasks, progress updates, approvals, comments, attachments.
- Creating meetings, participant selection, minutes and decisions.
- Google Calendar / automatic Meet link generation (requires Google OAuth setup).
- Firebase push notifications and scheduled reminder jobs.
- Department management, reports, document management, lab inventory, events, professional development, student monitoring.

## Project layout

```
lib/
  main.dart                 startup, Supabase init
  app.dart                  router, auth redirect, theme, locales
  core/                     config (dart-define), theme/colours
  features/
    auth/                   login, setup-required screen
    home/                   bottom-nav shell, dashboard
    tasks/                  task list
    meetings/               meeting list
    notifications/          notification centre
    profile/                profile and sign-out
    teachers/               staff directory
  shared/providers/         Riverpod data providers (Supabase queries)
supabase/migrations/
  0001_core_schema.sql      tables, enums, indexes, triggers
  0002_rls_policies.sql     security helpers and RLS policies
scripts/
  bootstrap_android.sh      generates android/ and applies app ID, label, INTERNET permission
  build_apk.sh              release build with secrets from environment
.github/workflows/
  build-apk.yml             cloud APK build (needs repo secrets)
docs/
  SETUP.md                  full setup and build guide
```

## Quick start

Follow **[docs/SETUP.md](docs/SETUP.md)**. In short:

```bash
bash scripts/bootstrap_android.sh
export SUPABASE_URL="https://YOUR-PROJECT.supabase.co"
export SUPABASE_ANON_KEY="YOUR_ANON_PUBLIC_KEY"
bash scripts/build_apk.sh
```

Output: `build/app/outputs/flutter-apk/app-release.apk`

## Security model

- The app ships only the public anon key. The service role key is never included.
- Every permission is checked in PostgreSQL (RLS), not only in the UI.
- Clients cannot create accounts; only an administrator can, and public sign-up is off.
- Assignees cannot set a task to *completed* or *revision required*. A trigger enforces this.
- Notifications can be read and marked read only by their owner.
