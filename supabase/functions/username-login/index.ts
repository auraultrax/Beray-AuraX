import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || '';
const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';
const AUTH_API_KEY = Deno.env.get('SUPABASE_ANON_KEY') || Deno.env.get('SUPABASE_PUBLISHABLE_KEY') || '';
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status, headers: { ...corsHeaders, 'Content-Type': 'application/json; charset=utf-8' },
});

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return json({ error: 'Yalnızca POST isteği kabul edilir.' }, 405);
  if (!SUPABASE_URL || !SERVICE_KEY || !AUTH_API_KEY) {
    console.error('username-login yapılandırması eksik.');
    return json({ error: 'Giriş servisi henüz yapılandırılmadı. Supabase Edge Function ayarlarını kontrol edin.' }, 500);
  }

  try {
    const body = await req.json().catch(() => ({}));
    const username = typeof body?.username === 'string' ? body.username.trim() : '';
    const password = typeof body?.password === 'string' ? body.password : '';
    if (!/^[a-zA-Z0-9._-]{3,40}$/.test(username) || !password || password.length > 1024) {
      return json({ error: 'Hatalı kullanıcı adı veya şifre.' }, 400);
    }

    const admin = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false, autoRefreshToken: false } });
    const { data: identity, error: lookupError } = await admin.rpc('aurax_lookup_username_login', { p_username: username });
    if (lookupError) {
      console.error('username-login kullanıcı sorgusu başarısız:', lookupError.code, lookupError.message);
      return json({ error: 'Giriş servisi hazır değil. Önce Aura X temel SQL kurulumunu tamamlayın.' }, 500);
    }
    const email = typeof identity?.authEmail === 'string' ? identity.authEmail.trim().toLowerCase() : '';
    const expectedUid = typeof identity?.authUid === 'string' ? identity.authUid : '';
    if (!email || !expectedUid) return json({ error: 'Hatalı kullanıcı adı veya şifre.' }, 401);

    // The password is sent only to Supabase Auth; it is never stored or logged here.
    const authResponse = await fetch(`${SUPABASE_URL}/auth/v1/token?grant_type=password`, {
      method: 'POST',
      headers: {
        apikey: AUTH_API_KEY,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ email, password }),
    });
    const authPayload = await authResponse.json().catch(() => ({}));
    if (!authResponse.ok || !authPayload?.access_token || !authPayload?.refresh_token || String(authPayload?.user?.id || '') !== expectedUid) {
      return json({ error: 'Hatalı kullanıcı adı veya şifre.' }, 401);
    }
    return json({ session: authPayload });
  } catch (error) {
    console.error('username-login beklenmeyen hata:', (error as any)?.message || 'unknown');
    return json({ error: 'Giriş sırasında beklenmeyen bir hata oluştu. Biraz sonra tekrar deneyin.' }, 500);
  }
});
