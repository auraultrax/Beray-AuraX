import { createClient } from 'npm:@supabase/supabase-js@2';

// AURAI arama: Google Custom Search ile not toplar. Yalnızca giriş yapmış kullanıcılar.
// Secret'lar: GOOGLE_CSE_KEY (API anahtarı), GOOGLE_CSE_CX (Programmable Search Engine kimliği).
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return json({ error: 'Method Not Allowed' }, 405);

  const jwt = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!;
  if (!jwt || jwt === anonKey) return json({ error: 'Yetkisiz.' }, 401);
  const authClient = createClient(supabaseUrl, anonKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: authData, error: authError } = await authClient.auth.getUser(jwt);
  if (authError || !authData?.user) return json({ error: 'Yetkisiz.' }, 401);

  const key = Deno.env.get('GOOGLE_CSE_KEY');
  const cx = Deno.env.get('GOOGLE_CSE_CX');
  if (!key || !cx) return json({ error: 'Arama anahtarı tanımlı değil. Supabase Secrets bölümünde GOOGLE_CSE_KEY ve GOOGLE_CSE_CX değerlerini ekle.', code: 'SEARCH_NOT_CONFIGURED' }, 503);

  let body: any;
  try { body = await req.json(); } catch { return json({ error: 'İstek okunamadı.' }, 400); }
  const query = String(body?.query || '').trim().slice(0, 200);
  if (!query) return json({ error: 'Aranacak bir şey yazmalısın.' }, 400);

  try {
    const u = 'https://www.googleapis.com/customsearch/v1?key=' + encodeURIComponent(key) +
      '&cx=' + encodeURIComponent(cx) + '&q=' + encodeURIComponent(query) + '&num=5&hl=tr&gl=tr';
    const r = await fetch(u, { signal: AbortSignal.timeout(15000) });
    const d: any = await r.json().catch(() => ({}));
    if (!r.ok) {
      console.error('Google arama hatası:', r.status, JSON.stringify(d?.error ?? {}).slice(0, 300));
      return json({ error: 'Arama şu an yapılamadı (HTTP ' + r.status + '). Anahtarı ve arama motoru ayarlarını kontrol et.', code: 'SEARCH_HTTP' }, 502);
    }
    const items: any[] = Array.isArray(d?.items) ? d.items : [];
    const results = items.map((it) => ({
      title: String(it.title || ''),
      snippet: String(it.snippet || '').replace(/\s+/g, ' ').trim(),
      link: String(it.link || ''),
    }));
    return json({ results });
  } catch (e) {
    console.error('aurai-search error', e);
    return json({ error: 'Arama sırasında bağlantı hatası oluştu.', code: 'SEARCH_FAILED' }, 502);
  }
});
