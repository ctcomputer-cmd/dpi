// Edge Function: create a staff account (auth user + profile + roles + department).
// Only a logged-in super_admin or principal may call it. Uses the service role
// key that Supabase injects server-side; the key never reaches the Flutter app.
//
// Deploy:  supabase functions deploy create-staff
import { createClient } from "npm:@supabase/supabase-js@2.45.4";

const ALLOWED_ROLES = [
  "principal",
  "hod",
  "coordinator",
  "teacher",
  "lab_incharge",
  "event_coordinator",
];

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const url = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  // 1. Who is calling? Use the caller's own token.
  const authHeader = req.headers.get("Authorization") ?? "";
  const caller = createClient(url, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: userData } = await caller.auth.getUser();
  const callerId = userData?.user?.id;
  if (!callerId) return json({ error: "Not signed in" }, 401);

  const admin = createClient(url, serviceKey, {
    auth: { persistSession: false },
  });

  // 2. Is the caller allowed to create staff?
  const { data: roleRows } = await admin
    .from("user_roles")
    .select("role")
    .eq("user_id", callerId);
  const canCreate = (roleRows ?? []).some(
    (r) => r.role === "super_admin" || r.role === "principal",
  );
  if (!canCreate) return json({ error: "Forbidden" }, 403);

  // 3. Validate input.
  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON" }, 400);
  }

  const email = String(body.email ?? "").trim().toLowerCase();
  const fullName = String(body.full_name ?? "").trim();
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
    return json({ error: "Invalid email" }, 400);
  }
  if (fullName.length < 2 || fullName.length > 120) {
    return json({ error: "Invalid name" }, 400);
  }

  const roles = Array.isArray(body.roles) ? body.roles.map(String) : [];
  if (roles.some((r) => !ALLOWED_ROLES.includes(r))) {
    return json({ error: "Invalid role" }, 400);
  }

  const optional = (v: unknown) => {
    const s = String(v ?? "").trim();
    return s.length ? s : null;
  };

  // 4. Create the login. Supabase emails the new user a link to set a password,
  //    so no password is ever typed, shown or stored by the app.
  const { data: invited, error: inviteErr } = await admin.auth.admin
    .inviteUserByEmail(email, { data: { full_name: fullName } });
  if (inviteErr || !invited?.user) {
    return json({ error: inviteErr?.message ?? "Could not create account" }, 400);
  }
  const newId = invited.user.id;

  // 5. Profile, roles, department membership, audit trail.
  const { error: profErr } = await admin.from("profiles").upsert({
    id: newId,
    full_name: fullName,
    email,
    employee_id: optional(body.employee_id),
    designation: optional(body.designation),
    phone: optional(body.phone),
    bio: optional(body.bio),
    joining_date: optional(body.joining_date),
    is_active: true,
    created_by: callerId,
    updated_by: callerId,
  });
  if (profErr) return json({ error: profErr.message }, 400);

  if (roles.length > 0) {
    await admin.from("user_roles").insert(roles.map((role) => ({ user_id: newId, role })));
  }
  if (optional(body.department_id)) {
    await admin.from("department_memberships").insert({
      user_id: newId,
      department_id: String(body.department_id),
    });
  }

  await admin.from("audit_logs").insert({
    actor_id: callerId,
    action: "staff.create",
    target_table: "profiles",
    target_id: newId,
    details: { email, roles },
  });

  return json({ user_id: newId }, 200);
});
