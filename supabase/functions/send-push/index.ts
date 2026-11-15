// Sends a phone notification for each new row in `notifications`.
// Triggered by a Supabase Database Webhook (INSERT on notifications).
//
// Secrets to set in Supabase (Edge Functions -> Secrets):
//   FCM_SERVICE_ACCOUNT  = full text of the Firebase service account JSON
//   WEBHOOK_SECRET       = any long random text (must match the webhook header)
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are provided automatically.

import { createClient } from "npm:@supabase/supabase-js@2.45.4";
import { SignJWT, importPKCS8 } from "npm:jose@5.9.6";

type ServiceAccount = { client_email: string; private_key: string; project_id: string };

const account: ServiceAccount = JSON.parse(Deno.env.get("FCM_SERVICE_ACCOUNT") ?? "{}");
const sb = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

let cached: { token: string; exp: number } | null = null;

/** Google OAuth access token for the Firebase Messaging API (cached until near expiry). */
async function accessToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cached && cached.exp - 60 > now) return cached.token;

  const key = await importPKCS8(account.private_key, "RS256");
  const assertion = await new SignJWT({ scope: "https://www.googleapis.com/auth/firebase.messaging" })
    .setProtectedHeader({ alg: "RS256" })
    .setIssuer(account.client_email)
    .setAudience("https://oauth2.googleapis.com/token")
    .setIssuedAt(now)
    .setExpirationTime(now + 3600)
    .sign(key);

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  const json = await res.json();
  if (!res.ok) throw new Error("token error: " + JSON.stringify(json));
  cached = { token: json.access_token, exp: now + json.expires_in };
  return json.access_token;
}

Deno.serve(async (req) => {
  const secret = Deno.env.get("WEBHOOK_SECRET");
  if (secret && req.headers.get("x-webhook-secret") !== secret) {
    return new Response("forbidden", { status: 403 });
  }

  const payload = await req.json();
  const n = payload.record;
  if (!n?.user_id) return Response.json({ sent: 0 });

  const { data: tokens, error } = await sb
    .from("device_tokens")
    .select("token")
    .eq("user_id", n.user_id);
  if (error) return new Response(error.message, { status: 500 });

  let sent = 0;
  for (const t of tokens ?? []) {
    const res = await fetch(
      `https://fcm.googleapis.com/v1/projects/${account.project_id}/messages:send`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${await accessToken()}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          message: {
            token: t.token,
            notification: { title: n.title, body: n.body ?? "" },
            data: { link: n.link ?? "/notifications" },
            android: { priority: "high" },
          },
        }),
      },
    );
    if (res.ok) {
      sent++;
    } else if (res.status === 404 || res.status === 400) {
      // Token is no longer valid (app removed or reinstalled): forget it.
      await sb.from("device_tokens").delete().eq("token", t.token);
    }
  }
  return Response.json({ sent });
});
