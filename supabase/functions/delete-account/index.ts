import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { ...corsHeaders, "Content-Type": "application/json; charset=utf-8" },
});

async function getAllRows(admin: any, table: string) {
  const all: Array<{ id: string; data: Record<string, unknown> }> = [];
  for (let start = 0; start < 10000; start += 1000) {
    const { data, error } = await admin.from(table).select("id,data").range(start, start + 999);
    if (error) throw new Error(`${table} tablosu okunamadı: ${error.message}`);
    const rows = (data || []) as Array<{ id: string; data: Record<string, unknown> }>;
    all.push(...rows);
    if (rows.length < 1000) break;
  }
  return all;
}

async function deleteIds(admin: any, table: string, ids: string[]) {
  for (let start = 0; start < ids.length; start += 100) {
    const part = ids.slice(start, start + 100);
    if (!part.length) continue;
    const { error } = await admin.from(table).delete().in("id", part);
    if (error) throw new Error(`${table} kayıtları silinemedi: ${error.message}`);
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Yalnızca POST desteklenir." }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") || Deno.env.get("SUPABASE_PUBLISHABLE_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !anonKey || !serviceKey) return json({ error: "Supabase Edge Function ortam değişkenleri eksik." }, 500);

  const authHeader = req.headers.get("Authorization") || "";
  const token = authHeader.replace(/^Bearer\s+/i, "");
  if (!token) return json({ error: "Giriş oturumu gerekli." }, 401);

  const caller = createClient(supabaseUrl, anonKey, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: `Bearer ${token}` } },
  });
  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: authData, error: authError } = await caller.auth.getUser(token);
  if (authError || !authData?.user) return json({ error: "Oturum doğrulanamadı." }, 401);
  const authUser = authData.user;

  let requestedUsername = "";
  try {
    const payload = await req.json();
    requestedUsername = String(payload?.username || "").trim();
  } catch {
    return json({ error: "İstek gövdesi geçersiz." }, 400);
  }

  // Kullanıcı adını istemciden güvenilir kabul etmiyoruz: önce Auth UID eşlemesini doğrula.
  const { data: linkRow, error: linkError } = await admin.from("account_links")
    .select("id,data").eq("id", authUser.id).maybeSingle();
  if (linkError) return json({ error: `Hesap eşlemesi okunamadı: ${linkError.message}` }, 500);
  let username = String(linkRow?.data?.username || "").trim();

  if (!username) {
    // Eski hesaplarda eşleme satırı yoksa yalnızca Auth UID'si aynı olan kullanıcı satırını kabul et.
    const { data: legacyUser, error: legacyError } = await admin.from("users")
      .select("id,data").eq("data->>authUid", authUser.id).maybeSingle();
    if (legacyError) return json({ error: `Hesap bilgisi okunamadı: ${legacyError.message}` }, 500);
    username = String(legacyUser?.id || "").trim();
  }
  if (!username) return json({ error: "Bu oturumla eşleşen Aura X hesabı bulunamadı." }, 404);
  if (requestedUsername && requestedUsername !== username) return json({ error: "İstenen kullanıcı adı giriş hesabıyla eşleşmiyor." }, 403);
  if (username.toUpperCase() === "A_UR_A_XX") return json({ error: "Sistem yönetici hesabı bu uç noktadan silinemez." }, 403);

  try {
    // Başka gönderilerin yorum/beğeni listelerinden de hesap referansını çıkar.
    const posts = await getAllRows(admin, "posts");
    for (const row of posts) {
      const d = row.data || {};
      if (String(d.author || "") === username) continue; // kendi gönderileri birazdan topluca silinir
      let changed = false;
      const next = { ...d };
      if (Array.isArray(d.likedBy) && d.likedBy.includes(username)) {
        next.likedBy = d.likedBy.filter((name) => name !== username); changed = true;
      }
      if (Array.isArray(d.comments)) {
        const comments = d.comments.filter((c: Record<string, unknown>) => String(c?.author || c?.username || "") !== username);
        if (comments.length !== d.comments.length) { next.comments = comments; changed = true; }
      }
      if (changed) {
        const { error } = await admin.from("posts").update({ data: next }).eq("id", row.id);
        if (error) throw new Error(`Gönderi etkileşimleri temizlenemedi: ${error.message}`);
      }
    }

    // Oda üyelikleri, kullanıcının eski mesajları ve mesaj tepkileri temizlenir.
    const rooms = await getAllRows(admin, "rooms");
    for (const row of rooms) {
      const d = row.data || {};
      const next: Record<string, unknown> = { ...d };
      let changed = false;
      if (Array.isArray(d.members) && d.members.includes(username)) {
        next.members = d.members.filter((name) => name !== username); changed = true;
      }
      if (Array.isArray(d.messages)) {
        const messages = d.messages.filter((m: Record<string, unknown>) => String(m?.author || "") !== username)
          .map((m: Record<string, unknown>) => {
            const reactions = (m?.reactions && typeof m.reactions === "object") ? { ...(m.reactions as Record<string, unknown>) } : null;
            if (!reactions) return m;
            let reactionChanged = false;
            for (const [emoji, people] of Object.entries(reactions)) {
              if (Array.isArray(people) && people.includes(username)) {
                reactions[emoji] = people.filter((name) => name !== username); reactionChanged = true;
              }
            }
            if (reactionChanged) { changed = true; return { ...m, reactions }; }
            return m;
          });
        if (messages.length !== d.messages.length) { next.messages = messages; changed = true; }
      }
      if (changed) {
        const { error } = await admin.from("rooms").update({ data: next }).eq("id", row.id);
        if (error) throw new Error(`Oda verileri temizlenemedi: ${error.message}`);
      }
    }

    // Kullanıcıya bağlı belge tablolarını temizle. Generic Aura X tabloları {id, data jsonb} biçimindedir.
    const notifications = await getAllRows(admin, "notifications");
    await deleteIds(admin, "notifications", notifications.filter(r => r.data?.to === username || r.data?.from === username).map(r => r.id));
    const votes = await getAllRows(admin, "votes");
    await deleteIds(admin, "votes", votes.filter(r => r.data?.voter === username || r.data?.target === username).map(r => r.id));
    const reports = await getAllRows(admin, "reports");
    await deleteIds(admin, "reports", reports.filter(r => r.data?.reportedBy === username || r.data?.author === username || r.data?.from === username).map(r => r.id));
    const pushRows = await getAllRows(admin, "push_tokens");
    await deleteIds(admin, "push_tokens", pushRows.filter(r => r.data?.username === username).map(r => r.id));

    // Gönderilerin belge kimliği genellikle rastgeledir; hesabın tüm gönderilerini yazardaki kullanıcı adına göre sil.
    await deleteIds(admin, "posts", posts.filter(r => String(r.data?.author || r.data?.username || "") === username).map(r => r.id));

    for (const table of ["statuses", "restrictions", "restriction_codes", "banned_users"]) {
      const { error } = await admin.from(table).delete().eq("id", username);
      if (error && !/does not exist|schema cache/i.test(error.message)) throw new Error(`${table} kaydı silinemedi: ${error.message}`);
    }
    const { error: userError } = await admin.from("users").delete().eq("id", username);
    if (userError) throw new Error(`Profil silinemedi: ${userError.message}`);
    const { error: linkDeleteError } = await admin.from("account_links").delete().eq("id", authUser.id);
    if (linkDeleteError) throw new Error(`Hesap bağlantısı silinemedi: ${linkDeleteError.message}`);

    // Kullanıcının kendi medya nesnelerini temizlemeye çalış; veri silme bunun başarısına bağlı değildir.
    try {
      const bucket = admin.storage.from("media");
      for (const folder of ["avatars", "postImages", "postVideos", "statusImages", "statusVideos"]) {
        const { data: files } = await bucket.list(folder, { limit: 1000 });
        const names = (files || []).filter((f) => f.name.startsWith(`${username}_`)).map((f) => `${folder}/${f.name}`);
        if (names.length) await bucket.remove(names);
      }
      const { data: stickers } = await bucket.list(`stickers/${username}`, { limit: 1000 });
      if (stickers?.length) await bucket.remove(stickers.map((f) => `stickers/${username}/${f.name}`));
    } catch (storageError) {
      console.warn("Kullanıcı medya dosyaları temizlenemedi:", storageError);
    }

    const { error: authDeleteError } = await admin.auth.admin.deleteUser(authUser.id);
    if (authDeleteError) throw new Error(`Supabase Auth hesabı silinemedi: ${authDeleteError.message}`);

    return json({ ok: true, message: "Aura X hesabı ve erişilebilen ilişkili verileri silindi." });
  } catch (error) {
    console.error("delete-account failed", error);
    return json({ error: error instanceof Error ? error.message : "Hesap silme işlemi başarısız." }, 500);
  }
});
