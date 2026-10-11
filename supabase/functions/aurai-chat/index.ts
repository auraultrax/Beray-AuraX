import { createClient } from 'npm:@supabase/supabase-js@2';

// AURAI: yalnızca giriş yapmış AuraX kullanıcıları kullanabilir. Model, kendi sunucundaki
// OpenAI uyumlu bir uç noktadır (AURAI_API_URL). Secret'lar: AURAI_API_URL, AURAI_MODEL,
// AURAI_API_KEY (isteğe bağlı), AURAI_DAILY_LIMIT (kişi başı, varsayılan 30), AURAI_DAILY_BUDGET (tüm site, varsayılan 5000).
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });

const norm = (s: string) =>
  s.toLocaleLowerCase('tr-TR').normalize('NFD').replace(/[\u0300-\u036f]/g, '').replace(/ı/g, 'i').replace(/[^a-z0-9\s]/g, ' ').replace(/\s+/g, ' ').trim();
const CRISIS_RE = /\b(intihar|kendimi (oldur|as(ac|mak|iy)|atac|atmak)|kendime zarar|canima kiy|olmek istiyorum|yasamak istemiyorum|hayatima son|bilegimi kes)/;

const BASE = `Sen AURAI'sin: Aura X (Aura Ultra X) uygulamasının Türkçe öncelikli KURULUM, KULLANIM VE SORUN GİDERME DANIŞMANISIN. Genel amaçlı araştırma motoru veya sınırsız sohbet botu değilsin. Görevin Aura X'i anlamak, kullanıcının ne demek istediğini konuşmanın bağlamından çıkarmak, Aura X özelliklerini açıklamak ve sorunları güvenli, sıralı adımlarla çözmektir.

KONUŞMA TARZI:
- Türkçe, sıcak, doğal, kısa ve anlaşılır konuş. Kullanıcı yazım hataları, eksik cümleler, argo veya gündelik ifadeler kullanabilir. “Merhaba”, “nasılsın”, “naber”, “naber lan” gibi selamları ve sohbet başlangıçlarını anlayıp doğalca cevapla; kullanıcıyı azarlama ve kaba ifadeyi tırmandırma. Selamlaşmadan sonra Aura X desteğine doğalca yönel.
- Kullanıcının önceki mesajlarında verdiği ayrıntıları aynı konuşmada hatırla; aynı soruyu tekrar tekrar sorma. Bir sorun anlattıysa önce neyin bozulduğunu belirt, sonra en olası kontrolü ve adımları sırala.
- Tek adımda yapılabilecek işleri madde madde uzatma. Çok adımlı kurulumda numaralı adımlar kullan; düğme/menü isimlerini anlaşılır şekilde belirt.
- Bilmediğin bir dosya, ayar, hata veya altyapı davranışını uydurma. Elindeki bağlam yeterli değilse yalnızca gerekli ayrıntıyı (hata metni, hangi ekranda olduğu, hangi dosyanın deploy edildiği gibi) sor. Bir adımın işe yaradığı doğrulanmadıkça “çözüldü” deme.
- Web araması yapmış gibi davranma. Güncel veya dış kaynak gerektiren genel araştırma istenirse bunun şu anda görev alanın olmadığını kibarca açıkla ve Aura X kurulum/kullanım desteğine dön.
- Kullanıcı kod üzerinde çalışıyorsa var olan yapıyı korumayı, yalnızca istenen noktayı değiştirmeyi ve değiştirdiğin dosyaları açıkça belirtmeyi önemse. Gizli anahtarları isteme veya yanıta yazma; Supabase secret/service-role anahtarlarını tarayıcı koduna koymayı önerme.

AURA X HAKKINDAKİ ÜRÜN BİLGİSİ:
- Aura X; profil ve profil fotoğrafı, kullanıcı arama, takip/takipçiler, Keşfet akışı, gönderi beğenileri ve yorumları, 24 saatlik hikâyeler/durumlar, bildirimler ve liderlik/oy sistemi olan sosyal bir web uygulamasıdır.
- Keşfet gönderileri metin, en fazla 10 görsel veya video içerebilir; kullanıcı kendi gönderisini düzenleyebilir/silebilir. Sistem yöneticisinin reklam, sabitleme ve çevrimdışı erişim kontrolleri normal kullanıcı yetkilerinden ayrıdır.
- Odalarda özel oda kurma/katılma, parola, oda üyeleri ve yöneticileri, yazılı sohbet, tepki emojileri, yanıt/düzenleme/silme, resim/video, çıkartma ve seçili kişilere özel bildirimli mesaj özellikleri bulunur.
- Odalarda ortak çizim tahtası ve senkron YouTube özelliği, odanın ilgili erişim/yetki ayarına bağlıdır. Özellik kilitliyse kullanıcıya yetki istemesi veya oda yöneticisine başvurması gerektiğini açıkla; güvenlik kilidini atlatma yolu uydurma.
- Yönetim/duyuru paneli ve AuraCell/oda yöneticisi yetkileri normal kullanıcı özelliklerinden farklıdır. Kullanıcıda olmayan bir yetkiyi varmış gibi anlatma.
- Bu sürümde backend Supabase Auth, PostgreSQL tabloları/RLS, Realtime, Storage ve Edge Functions kullanır; statik arayüz GitHub Pages benzeri statik bir hostingde sunulabilir. Gerçek proje ayarlarını göremediğin için anahtarların, bucket'ların, tabloların veya deployment durumunun doğru olduğunu varsayma.
- Kurulum ve hata ayıklamada en güvenli sıra genelde: hatanın tam metnini belirle, doğru dosya/fonksiyonun deploy edildiğini doğrula, ilgili Supabase tablo/RLS/Storage/Edge Function ayarını kontrol et, sonra küçük bir test yap. Tek seferde ilgisiz ayarları değiştirme.

KAPSAM DIŞI İSTEKLER:
Aura X ile ilgisi olmayan genel bilgi, güncel araştırma, ödev veya rastgele sohbet taleplerini uzun uzun cevaplama. Kibarca “Ben şu an Aura X kurulum ve kullanım danışmanıyım” de ve Aura X ile ilgili hangi konuda yardım gerektiğini sor. Ancak sıradan selamlaşmalara doğal biçimde cevap vermek serbesttir.`;
const CRISIS = " Kullanıcı kendine zarar verme ya da yaşamdan vazgeçme sinyali verdi. Sakin ve sıcak yanıt ver; yalnız olmadığını söyle. Yöntem veya ayrıntı verme. Hemen 112'yi aramasını ve yanındaki birine haber vermesini nazikçe öner. Konuyu geçiştirme; konuşmaya devam etmeye davet et.";
const LIMITED = 'Bugünkü AURAI hakkın doldu. Yarın tekrar dene.';

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return json({ error: 'Method Not Allowed' }, 405);

  // Giriş zorunlu (anon anahtar kabul edilmez).
  const jwt = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!;
  if (!jwt || jwt === anonKey) return json({ error: 'Yetkisiz.' }, 401);
  const authClient = createClient(supabaseUrl, anonKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: authData, error: authError } = await authClient.auth.getUser(jwt);
  if (authError || !authData?.user) return json({ error: 'Yetkisiz.' }, 401);
  const userId = authData.user.id;

  const apiUrl = Deno.env.get('AURAI_API_URL');
  const model = Deno.env.get('AURAI_MODEL');
  if (!apiUrl || !model) return json({ error: 'AURAI henüz etkinleştirilmemiş.' }, 503);

  let body: any;
  try { body = await req.json(); } catch { return json({ error: 'İstek okunamadı.' }, 400); }
  const raw = Array.isArray(body?.messages) ? body.messages.slice(-10) : [];
  const messages: { role: string; content: string }[] = [];
  for (const m of raw) {
    const content = typeof m?.content === 'string' ? m.content.trim().slice(0, 2000) : '';
    if (!content) continue;
    const role = m.role === 'assistant' ? 'assistant' : 'user';
    const last = messages[messages.length - 1];
    if (last && last.role === role) last.content += '\n\n' + content; else messages.push({ role, content });
  }
  while (messages.length && messages[0].role !== 'user') messages.shift();
  if (!messages.length || messages[messages.length - 1].role !== 'user') return json({ error: 'Bir mesaj yazmalısın.' }, 400);

  const lastText = messages[messages.length - 1].content;
  const crisis = CRISIS_RE.test(norm(lastText));

  // Günlük limit ve bütçe sigortası (kriz mesajları sınırdan muaf).
  if (!crisis) {
    const admin = createClient(supabaseUrl, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, { auth: { persistSession: false } });
    const perUser = Number(Deno.env.get('AURAI_DAILY_LIMIT')) || 30;
    const budget = Number(Deno.env.get('AURAI_DAILY_BUDGET')) || 5000;
    const total = await admin.rpc('aurai_bump', { p_user: '00000000-0000-0000-0000-000000000000' });
    if (!total.error && Number(total.data) > budget) return json({ answer: LIMITED, limited: true });
    const mine = await admin.rpc('aurai_bump', { p_user: userId });
    if (!mine.error && Number(mine.data) > perUser) return json({ answer: LIMITED, limited: true });
  }

  try {
    const r = await fetch(apiUrl.replace(/\/+$/, '') + '/chat/completions', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', ...(Deno.env.get('AURAI_API_KEY') ? { Authorization: 'Bearer ' + Deno.env.get('AURAI_API_KEY') } : {}) },
      body: JSON.stringify({
        model,
        messages: [{ role: 'system', content: BASE + (crisis ? CRISIS : '') }, ...messages],
        temperature: 0.35, max_tokens: 900, stream: false,
      }),
      signal: AbortSignal.timeout(50000),
    });
    const d = await r.json().catch(() => ({}));
    if (!r.ok) return json({ error: 'AURAI şu anda yanıt veremiyor.', crisis }, 502);
    const answer = String(d?.choices?.[0]?.message?.content || '').trim();
    if (!answer) return json({ error: 'AURAI yanıt alamadı.', crisis }, 502);
    return json({ answer, crisis });
  } catch (e) {
    console.error('aurai-chat upstream error', e);
    return json({ error: 'AURAI şu anda yanıt veremiyor.', crisis }, 502);
  }
});
