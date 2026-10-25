import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || '';
const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status, headers: { ...corsHeaders, 'Content-Type': 'application/json; charset=utf-8' },
});

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return json({ error: 'Yalnızca POST isteği kabul edilir.' }, 405);
  if (!SUPABASE_URL || !SERVICE_KEY) return json({ error: 'Kullanıcı adı kontrol servisi yapılandırılmadı.' }, 500);
  try {
    const body = await req.json().catch(() => ({}));
    const username = typeof body?.username === 'string' ? body.username.trim() : '';
    if (!/^[a-zA-Z0-9._-]{3,40}$/.test(username)) return json({ available: false, error: 'Kullanıcı adı biçimi geçersiz.' }, 400);
    const admin = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false, autoRefreshToken: false } });
    const { data, error } = await admin.rpc('aurax_username_available', { p_username: username });
    if (error) {
      console.error('username-available sorgusu başarısız:', error.code, error.message);
      return json({ error: 'Kullanıcı adı kontrolü tamamlanamadı. Aura X temel SQL dosyasını kontrol edin.' }, 500);
    }
    return json({ available: data === true });
  } catch (error) {
    console.error('username-available beklenmeyen hata:', (error as any)?.message || 'unknown');
    return json({ error: 'Kullanıcı adı kontrolü sırasında hata oluştu.' }, 500);
  }
});
