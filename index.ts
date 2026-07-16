// supabase/functions/invite-user/index.ts
//
// Denne funktion kører på Supabase's servere — ALDRIG i browseren.
// Den er den eneste del af systemet, der har adgang til service_role-nøglen,
// og den bruger den udelukkende til at oprette den nye bruger, efter den har
// bekræftet, at den, der kalder funktionen, selv er logget ind som 'admin'.
//
// Deploy: supabase functions deploy invite-user

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return json({ error: "Ikke logget ind." }, 401);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    // Klient med den kaldendes egen JWT — bruges KUN til at slå identiteten op.
    const callerClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });

    const { data: { user }, error: userError } = await callerClient.auth.getUser();
    if (userError || !user) {
      return json({ error: "Ugyldig session." }, 401);
    }

    // Admin-klient med service_role — bruges til selve oprettelsen.
    // Denne nøgle forlader ALDRIG serveren.
    const adminClient = createClient(supabaseUrl, serviceRoleKey);

    const { data: callerProfile } = await adminClient
      .from("profiles")
      .select("role")
      .eq("id", user.id)
      .maybeSingle();

    if (!callerProfile || callerProfile.role !== "admin") {
      return json({ error: "Kun administratorer må oprette nye brugere." }, 403);
    }

    const { email, role } = await req.json();
    if (!email || !["admin", "redaktor"].includes(role)) {
      return json({ error: "Ugyldig e-mail eller rolle." }, 400);
    }

    // Sender en invitations-mail; brugeren sætter selv sin adgangskode via linket.
    const { data: invited, error: inviteError } = await adminClient.auth.admin.inviteUserByEmail(email);
    if (inviteError) {
      return json({ error: inviteError.message }, 400);
    }

    const { error: profileError } = await adminClient
      .from("profiles")
      .upsert({ id: invited.user.id, email, role }, { onConflict: "id" });

    if (profileError) {
      return json({ error: profileError.message }, 400);
    }

    return json({ success: true, userId: invited.user.id });
  } catch (err) {
    return json({ error: String(err) }, 500);
  }
});
