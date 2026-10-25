import { createClient } from 'npm:@supabase/supabase-js@2';

// AURAI arama proxy'si: anahtarlar istemciye gönderilmez; yalnızca oturum açmış kullanıcılar erişebilir.
// Secrets: GOOGLE_CSE_KEY, GOOGLE_CSE_CX. Günlük sayaç ayarları aurai-chat ile ortaktır.
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-supabase-api-version',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { ...corsHeaders, 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' },
});
const GLOBAL_USAGE_ID = '00000000-0000-0000-0000-000000000000';

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return json({ error: 'Method Not Allowed' }, 405);

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!supabaseUrl || !anonKey) return json({ error: 'Arama kimlik doğrulama yapılandırması eksik.', code: 'AUTH_CONFIG_MISSING' }, 503);

  const jwt = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
  if (!jwt || jwt === anonKey) return json({ error: 'Yetkisiz.' }, 401);
  const authClient = createClient(supabaseUrl, anonKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: authData, error: authError } = await authClient.auth.getUser(jwt);
  if (authError || !authData?.user) return json({ error: 'Yetkisiz.' }, 401);

  const key = Deno.env.get('AIzaSyAlY5yTDwsp0bhZjmYqR_MBZ3MCJ5QdRDg');
  const cx = Deno.env.get('e744e35067d87480d');
  if (!key || !cx) return json({ error: 'Arama servisi yapılandırılmamış. Supabase Secrets bölümünde GOOGLE_CSE_KEY ve GOOGLE_CSE_CX değerlerini ekleyin.', code: 'SEARCH_NOT_CONFIGURED' }, 503);

  let body: any;
  try { body = await req.json(); } catch { return json({ error: 'İstek okunamadı.' }, 400); }
  const query = String(body?.query || '').trim().slice(0, 200);
  if (!query) return json({ error: 'Aranacak bir şey yazmalısın.' }, 400);

  // Bir kullanıcının anahtarı sınırsız tüketmesini ve kurulumda kota tablosu yokken modele/arama API'sine gidilmesini önle.
  if (!serviceRoleKey) return json({ error: 'AURAI kullanım sınırı yapılandırılmamış.', code: 'USAGE_LIMITER_CONFIG_MISSING' }, 503);
  const admin = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const budget = Math.max(1, Number(Deno.env.get('AURAI_DAILY_BUDGET')) || 5000);
  const perUser = Math.max(1, Number(Deno.env.get('AURAI_SEARCH_DAILY_LIMIT')) || 10);
  const total = await admin.rpc('aurai_bump', { p_user: GLOBAL_USAGE_ID, p_feature: 'global' });
  if (total.error || !Number.isFinite(Number(total.data))) {
    console.error('AURAI arama global sayacı hatası:', total.error?.message || 'geçersiz sayaç sonucu');
    return json({ error: 'AURAI kullanım sınırı hazır değil. supabase/aurai_usage_setup.sql dosyasını çalıştırın.', code: 'USAGE_LIMITER_UNAVAILABLE' }, 503);
  }
  if (Number(total.data) > budget) return json({ error: 'AURAI günlük toplam kullanım sınırına ulaştı. Yarın tekrar deneyin.', code: 'DAILY_BUDGET_REACHED' }, 429);

  const mine = await admin.rpc('aurai_bump', { p_user: authData.user.id, p_feature: 'search' });
  if (mine.error || !Number.isFinite(Number(mine.data))) {
    console.error('AURAI arama kullanıcı sayacı hatası:', mine.error?.message || 'geçersiz sayaç sonucu');
    return json({ error: 'AURAI kullanım sınırı hazır değil. supabase/aurai_usage_setup.sql dosyasını çalıştırın.', code: 'USAGE_LIMITER_UNAVAILABLE' }, 503);
  }
  if (Number(mine.data) > perUser) return json({ error: 'Bugünkü internet arama hakkın doldu. Yarın tekrar deneyebilirsin.', code: 'SEARCH_DAILY_LIMIT' }, 429);

  try {
    const url = 'https://www.googleapis.com/customsearch/v1?key=' + encodeURIComponent(key) +
      '&cx=' + encodeURIComponent(cx) + '&q=' + encodeURIComponent(query) + '&num=5&hl=tr&gl=tr';
    const response = await fetch(url, { signal: AbortSignal.timeout(15000) });
    const data: any = await response.json().catch(() => ({}));
    if (!response.ok) {
      console.error('Google arama hatası:', response.status, JSON.stringify(data?.error ?? {}).slice(0, 300));
      return json({ error: response.status === 429
        ? 'Arama sağlayıcısının geçici sınırına ulaşıldı. Biraz bekleyip tekrar dene.'
        : 'Arama şu anda yapılamadı. Arama anahtarı ve arama motoru ayarları kontrol edilmeli.', code: 'SEARCH_HTTP' }, 502);
    }
    const items: any[] = Array.isArray(data?.items) ? data.items : [];
    const results = items.slice(0, 5).map((item) => {
      let link = '';
      try {
        const candidate = new URL(String(item?.link || ''));
        if (candidate.protocol === 'https:' || candidate.protocol === 'http:') link = candidate.href;
      } catch (_) { /* geçersiz bağlantıyı yanıttan çıkar */ }
      return {
        title: String(item?.title || '').slice(0, 300),
        snippet: String(item?.snippet || '').replace(/\s+/g, ' ').trim().slice(0, 900),
        link,
      };
    }).filter((item) => item.title || item.snippet || item.link);
    return json({ results });
  } catch (error) {
    console.error('aurai-search error', error);
    const timeout = error instanceof Error && (error.name === 'TimeoutError' || error.name === 'AbortError');
    return json({ error: timeout ? 'Arama zaman aşımına uğradı. Tekrar deneyebilirsin.' : 'Arama sırasında bağlantı hatası oluştu.', code: timeout ? 'SEARCH_TIMEOUT' : 'SEARCH_FAILED' }, 502);
  }
});
