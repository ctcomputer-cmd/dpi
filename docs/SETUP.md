# DPI Department Hub - Setup and APK Build Guide

This guide covers everything needed to run the app against a real backend and build an installable APK.

## What must be done by a person (cannot be automated)

These steps need your own accounts and identity, so they cannot be done by the code:

| Item | Why it's needed | Where |
|---|---|---|
| Supabase project | Database, login, storage | https://supabase.com |
| Firebase project (later) | Push notifications | https://console.firebase.google.com |
| Google Cloud project (later) | Automatic Google Meet links | https://console.cloud.google.com |
| Flutter SDK + Android SDK on your PC | Building the APK | https://docs.flutter.dev/get-started/install |

Until Firebase and Google are set up, the app works with the manual Meet-link fallback.

---

## 1. Install the tools (one-time)

1. **Flutter** (stable 3.27 or newer): follow https://docs.flutter.dev/get-started/install
2. **JDK 17** (Android Studio bundles one).
3. **Android SDK**: install Android Studio, open *SDK Manager*, install *Android SDK Platform 34* and *Build-Tools*.
4. Check everything:
   ```bash
   flutter doctor
   ```
   Resolve every item marked with a red cross before continuing.

## 2. Prepare the project

```bash
cd dpi_department_hub
bash scripts/bootstrap_android.sh
```

This generates the `android/` folder, sets the application ID to `bd.ac.dpi.departmenthub`, sets the app name to *DPI Department Hub*, and adds the INTERNET permission required by release builds.

## 3. Create the Supabase backend

1. Create a new project at https://supabase.com (choose the Singapore region for lower latency from Bangladesh).
2. In **SQL Editor**, run the files in this order:
   - `supabase/migrations/0001_core_schema.sql`
   - `supabase/migrations/0002_rls_policies.sql`
3. In **Project Settings → API**, copy:
   - **Project URL**
   - **anon public key**

   > Never copy or use the **service_role** key in the app. It bypasses all security.

4. In **Authentication → Providers**, keep *Email* enabled and **turn off "Allow new users to sign up"**. This keeps public registration disabled.

## 4. Create the first administrator

1. In Supabase: **Authentication → Users → Add user → Create new user**. Enter the admin email and a strong password, and tick *Auto Confirm User*.
2. In **SQL Editor**, run (replace the email and name):

   ```sql
   insert into public.profiles (id, full_name, email, designation, is_active)
   select id, 'Full Name', email, 'Principal', true
   from auth.users where email = 'admin@example.com';

   insert into public.user_roles (user_id, role)
   select id, 'super_admin' from auth.users where email = 'admin@example.com';
   ```

Further accounts are created the same way for now. A server-side Edge Function for in-app account creation is planned for Phase 1 (see Known limitations).

## 5. Build the APK

```bash
export SUPABASE_URL="https://YOUR-PROJECT.supabase.co"
export SUPABASE_ANON_KEY="YOUR_ANON_PUBLIC_KEY"
bash scripts/build_apk.sh
```

Output file:

```
build/app/outputs/flutter-apk/app-release.apk
```

For a debug build (faster, for testing): `flutter build apk --debug`.

## 6. Install on your phone

1. Copy `app-release.apk` to the phone (USB, Google Drive, or WhatsApp).
2. On the phone, allow *Install unknown apps* for the app you open the file with.
3. Tap the file and install.
4. Open **DPI Department Hub** and sign in with the admin account.

### Optional: Bangla and English fonts

1. Download *Inter* and *Noto Sans Bengali* (Google Fonts).
2. Place the `.ttf` files in `assets/fonts/`.
3. Add to `pubspec.yaml` under `flutter:` and set the font family in `lib/core/theme.dart`.

---

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| *Backend not configured* screen | The APK was built without `SUPABASE_URL` / `SUPABASE_ANON_KEY`. Rebuild with both set. |
| Login says invalid email or password | Wrong credentials, or the user was not created with *Auto Confirm*. |
| Dashboard shows "Could not load data" | Migrations were not run, or the user has no `profiles` row (see step 4). |
| Lists are empty for a non-admin | Expected: RLS shows only rows the user is allowed to see. Check department membership and roles. |
| Release APK cannot reach the internet | Confirm `android.permission.INTERNET` is in `android/app/src/main/AndroidManifest.xml`. |
