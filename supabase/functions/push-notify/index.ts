import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { ...corsHeaders, "Content-Type": "application/json; charset=utf-8" },
});

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Yalnızca POST desteklenir." }, 405);

  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") || Deno.env.get("SUPABASE_PUBLISHABLE_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const vapidPublic = Deno.env.get("WEB_PUSH_VAPID_PUBLIC_KEY");
  const vapidPrivate = Deno.env.get("WEB_PUSH_VAPID_PRIVATE_KEY");
  const vapidSubject = Deno.env.get("WEB_PUSH_VAPID_SUBJECT") || "mailto:xauraultra@gmail.com";
  if (!url || !anonKey || !serviceKey) return json({ error: "Supabase Edge Function ortam değişkenleri eksik." }, 500);
  if (!vapidPublic || !vapidPrivate) return json({ error: "Web Push VAPID anahtarları tanımlı değil." }, 503);

  const token = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
  if (!token) return json({ error: "Giriş oturumu gerekli." }, 401);
  const caller = createClient(url, anonKey, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: `Bearer ${token}` } },
  });
  const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: authData, error: authError } = await caller.auth.getUser(token);
  if (authError || !authData?.user) return json({ error: "Oturum doğrulanamadı." }, 401);

  let payload: { notificationId?: string } = {};
  try { payload = await req.json(); } catch { return json({ error: "Geçersiz istek gövdesi." }, 400); }
  const notificationId = String(payload.notificationId || "").trim();
  if (!notificationId) return json({ error: "notificationId zorunlu." }, 400);

  try {
    const { data: link, error: linkError } = await admin.from("account_links").select("data").eq("id", authData.user.id).maybeSingle();
    if (linkError) throw new Error(`Kullanıcı hesabı doğrulanamadı: ${linkError.message}`);
    const username = String(link?.data?.username || "").trim();
    if (!username) return json({ error: "Aura X hesabı bulunamadı." }, 403);

    const { data: row, error: notificationError } = await admin.from("notifications").select("id,data").eq("id", notificationId).maybeSingle();
    if (notificationError) throw notificationError;
    if (!row?.data) return json({ error: "Bildirim bulunamadı." }, 404);
    const notification = row.data as Record<string, unknown>;
    if (String(notification.from || "") !== username) return json({ error: "Bu bildirimi gönderme yetkiniz yok." }, 403);
    const recipient = String(notification.to || "").trim();
    if (!recipient || recipient === username) return json({ ok: true, sent: 0 });

    const { data: tokenRows, error: tokenError } = await admin.from("push_tokens")
      .select("id,data").eq("data->>username", recipient).limit(500);
    if (tokenError) throw tokenError;
    const subs = (tokenRows || []).filter((r) => r.data?.subscription?.endpoint && r.data?.subscription?.keys?.p256dh && r.data?.subscription?.keys?.auth);
    if (!subs.length) return json({ ok: true, sent: 0, reason: "no-subscriptions" });

    webpush.setVapidDetails(vapidSubject, vapidPublic, vapidPrivate);
    const payloadText = JSON.stringify({
      title: String(notification.title || (notification.type === "room_private" ? "Yeni özel mesaj · Aura X" : "Aura X bildirimi")),
      body: String(notification.text || "Yeni bildirimin var.").slice(0, 220),
      tag: `aurax-${notificationId}`,
      url: "./",
      roomId: notification.roomId || null,
      postId: notification.postId || null,
      notificationId,
    });

    let sent = 0;
    const staleIds: string[] = [];
    await Promise.all(subs.map(async (row) => {
      try {
        await webpush.sendNotification(row.data.subscription, payloadText, { TTL: 60 * 60 * 24 });
        sent += 1;
      } catch (err) {
        const statusCode = Number((err as { statusCode?: number })?.statusCode || 0);
        if (statusCode === 404 || statusCode === 410) staleIds.push(String(row.id));
        else console.warn("Web Push aboneliğine gönderilemedi:", statusCode, (err as Error)?.message || err);
      }
    }));
    if (staleIds.length) await admin.from("push_tokens").delete().in("id", staleIds);
    return json({ ok: true, sent, removedExpired: staleIds.length });
  } catch (error) {
    console.error("push-notify failed", error);
    return json({ error: error instanceof Error ? error.message : "Push bildirimi gönderilemedi." }, 500);
  }
});
