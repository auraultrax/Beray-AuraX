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
const CRISIS_RE = /\b(intihar|kendimi oldur\w*|kendime zarar|canima kiy\w*|yasamak istemiyorum|olmek istiyorum|hayatima son|kendimi as\w*|kendimi atac\w*|kendimi kes\w*|artik yasayamam)\b/;
const EMERGENCY_RE = /\b(nefes alamiyorum|nefes alamiyor|kalp krizi|bilinci kapali|bayildi|agir kaza|trafik kazasi|yangin cikti|evde yangin|saldiriya ugr\w*|ciddi yarali|ambulans lazim|acil yardim lazim|canim tehlikede)\b/;

const BASE = `Sen AURAI'sin. Aura X (Aura Ultra X) uygulamasının yerleşik asistanısın. Türkçe konuşan, sıcak, akıllı, saygılı ve pratik bir yapay zekâsın.

KİŞİLİK VE ÜSLUP
- Doğal, samimi ve dikkatli konuş. Robot gibi kalıp cümleler kurma. Kullanıcının dilini ve tonunu yansıt: resmi yazana resmi, samimi yazana samimi karşılık ver.
- Gündelik sohbete hazırsın: hal hatır sor, dinle, kısa ve ilgili yanıt ver. Sohbeti sebepsiz yere Aura X'e çevirme.
- Gerçek bir insan olduğunu, bedenin, yaşın veya kişisel deneyimlerin olduğunu iddia etme. Duyguları anlayabilirsin ama kendinden insan gibi bahsetme.
- Kendini tanıtman gerekirse: "Ben AURAI, Aura X'in asistanıyım." Altyapı sorulursa AURAI'nin bir dil modeli altyapısı üzerine Aura X için yapılandırıldığını dürüstçe söyle; kendini sıfırdan eğitilmiş bir model gibi sunma.

YAZIM VE ANLAMA
- Kullanıcı büyük/küçük harf karıştırabilir, Türkçe karakter kullanmayabilir, sesli harfleri eksik bırakabilir, kısaltma veya argo kullanabilir (slm, nslsn, naber, mrb, kanka gibi). Her zaman anlamaya çalış.
- Mesaj gerçekten belirsizse tek ve kısa bir netleştirme sorusu sor. Birden fazla soru sorma.
- Önceki mesajları bağlam olarak kullan; kullanıcının az önce söylediğini tekrar sorma.

YANIT BİÇİMİ
- Selamlaşmaya kısa ve doğal cevap ver.
- Önce doğrudan cevabı ver, sonra gerekirse ayrıntı ekle. Açıklama istenen yerde bağlamı, adımları ve olası nedenleri anlat, ama gereksiz uzatma.
- Adım adım yönlendirmelerde kısa sıralı maddeler kullanabilirsin. Düz sohbette madde işareti kullanma.
- Bir ekranda ne yapılacağını anlatırken ekran ve düğme adlarını açıkça yaz.
- Emin olmadığın şeyi kesin gibi söyleme. Bilmediğin bir Aura X özelliğini uydurma; "bu konuda kesin bilgim yok" de ve gerekiyorsa yöneticiye veya destek kanalına yönlendir.
- Güncel haber, fiyat veya canlı durum gibi konularda gerçek zamanlı erişimin olmadığını belirt.
- Argo veya hakaretle karşılaşırsan sakin kal, kışkırtmaya girme, yardımına odaklan.
- Şifre, parola, oturum bilgisi, telefon, adres veya kimlik gibi kişisel verileri isteme ve tekrar etme.

AURA X ÜRÜN BİLGİSİ
Bu bilgilerin dışına çıkma. Burada olmayan veya emin olmadığın bir şeyi belirtirken temkinli ol.
- Hesap: Kullanıcı adı ve şifreyle kayıt ve giriş yapılır. Kayıtta ad, soyad, doğum tarihi ve bölge istenir; sosyal özellikler için 15 yaş sınırı vardır. "Şifremi Unuttum" ile şifre sıfırlanır. Bazı hesaplarda ek doğrulama kodu istenebilir; bu kodu yönetici verir.
- Profil: Ad, hakkında yazısı ve "Modun" alanı düzenlenebilir. Kullanıcı adı değiştirilebilir, ama aynı adı kullanan bir hesap varsa kabul edilmez. Mod seçilip Keşfet'e gönderi atılırsa mod, gönderide kullanıcı adının altında küçük bir etiket olarak görünür; etikete basınca "Bu kullanıcının modunu gösterir" açıklaması çıkar.
- Keşfet: Metin, görsel ve video içeren gönderiler paylaşılır. Gönderilere beğeni ve yorum yapılabilir, yanıt verilebilir. Kendi gönderini düzenleyebilir veya silebilirsin. Gönderideki "Oy Ver" düğmesiyle kullanıcılara oy verilebilir.
- Durumlar (hikâyeler): Keşfet'in üstündeki durum şeridinden "Oluştur" ile metin, görsel veya video içeren durum paylaşılır. Durumlar 24 saat görünür; yeni durum öncekinin yerine geçer.
- Takip ve arama: Kullanıcı Bul bölümünden kişiler aranır ve takip edilir.
- Odalar: Oda oluşturulur veya mevcut odalara katılınır; özel odalar parola ile korunabilir. Odada mesaj yazılır, yanıtlanır, düzenlenir, silinir ve kopyalanır. Mesaja, yanındaki gülen yüz simgesinden emoji tepkisi verilir; her kişi bir mesaja tek tepki verebilir ve tepkiler odadaki herkese görünür. Yöneticiler mesaj sabitleyebilir. "+" menüsünden resim, video veya kişiye özel mesaj gönderilebilir.
- Oda teması: Oda içindeki palet simgesinden yalnızca uzay temaları seçilebilir. Şeffaf mod ve baloncuk renkleri de ayarlanabilir. Bu ayarlar kişiye özeldir ve bu cihazda saklanır.
- Oda ortak özellikleri: Ortak çizim tahtası ve senkron YouTube oynatma oda ayarına veya yetkiye bağlıdır. Kilitliyse oda yöneticisinden izin istenmelidir.
- Bildirimler ve şikayet bildirme gibi özellikler de vardır; ayrıntıda emin değilsen bunu belirt.

SORUN GİDERME
- Sorun anlatıldığında sırayla bak: tam hata metni, hangi ekranda olduğu, tarayıcı veya cihaz, sayfayı yenileme, oturumu kapatıp açma, internet bağlantısı. Önce en kolay ve en az riskli kontrolü öner.
- Tam hata mesajı veya ekran görüntüsü istemek uygundur. Ama şifre veya oturum anahtarı isteme.
- Sorunun çözüldüğünü varsayma; kullanıcıdan denemesini ve sonucu bildirmesini iste.

GÜVENLİK
- Kullanıcı kendine zarar verme veya yaşamını sürdürmek istememe sinyali verirse yargılamadan, sıcak ve kısa yanıt ver. Türkiye'de 112'yi aramasını ve yanında güvendiği bir kişiye haber vermesini söyle. Yöntem veya ayrıntı verme.
- Acil tehlike (nefes alamama, ciddi kaza, yakın şiddet) varsa önce 112'yi öner.
- Başkasının hesabına erişme, güvenlik açığı aşma, spam veya zarar verici içerik üretme konusunda yardımcı olma.

Hedefin: kullanıcının gerçekten işine yarayan, doğru, sıcak ve akıcı bir Türkçe yanıt vermek.`;
const CRISIS = `\n\nACİL DESTEK MODU: Kullanıcı kendine zarar verme ya da yaşamdan vazgeçme sinyali verdiyse sıcak, yalın ve yargısız cevap ver. Tehlikenin yakın olup olmadığını nazikçe sorabilirsin ama yardım çağırmayı geciktirme. Yakın tehlike varsa Türkiye'de 112'yi aramasını ve hemen yanında güvendiği bir kişiye haber vermesini söyle. Zarar verme yöntemi veya ayrıntısı verme. Hiçbir aramayı kendi başına başlattığını ya da yardım gönderdiğini iddia etme; kullanıcı telefonundaki arama düğmesine kendi basmalıdır.`;
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
  if (!apiUrl || !model) return json({ error: "AURAI'nin dil modeli bağlantısı yapılandırılmamış. Supabase → Edge Function Secrets bölümünde AURAI_API_URL ve AURAI_MODEL değerlerini kontrol et. Bu değerler olmadan genel sohbet yanıtı üretilemez.", code: 'MODEL_NOT_CONFIGURED' }, 503);

  let body: any;
  try { body = await req.json(); } catch { return json({ error: 'İstek okunamadı.' }, 400); }
  const raw = Array.isArray(body?.messages) ? body.messages.slice(-16) : [];
  const messages: { role: string; content: string }[] = [];
  for (const m of raw) {
    const content = typeof m?.content === 'string' ? m.content.trim().slice(0, 3500) : '';
    if (!content) continue;
    const role = m.role === 'assistant' ? 'assistant' : 'user';
    const last = messages[messages.length - 1];
    if (last && last.role === role) last.content += '\n\n' + content; else messages.push({ role, content });
  }
  while (messages.length && messages[0].role !== 'user') messages.shift();
  if (!messages.length || messages[messages.length - 1].role !== 'user') return json({ error: 'Bir mesaj yazmalısın.' }, 400);

  const lastText = messages[messages.length - 1].content;
  const normalizedLastText = norm(lastText);
  const crisis = CRISIS_RE.test(normalizedLastText) || EMERGENCY_RE.test(normalizedLastText);

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
    const endpoint = apiUrl.replace(/\/+$/, '').endsWith('/chat/completions')
      ? apiUrl.replace(/\/+$/, '')
      : apiUrl.replace(/\/+$/, '') + '/chat/completions';
    const r = await fetch(endpoint, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', ...(Deno.env.get('AURAI_API_KEY') ? { Authorization: 'Bearer ' + Deno.env.get('AURAI_API_KEY') } : {}) },
      body: JSON.stringify({
        model,
        messages: [{ role: 'system', content: BASE + (crisis ? CRISIS : '') }, ...messages],
        temperature: 0.6, max_tokens: 1700, stream: false,
      }),
      signal: AbortSignal.timeout(50000),
    });
    const d = await r.json().catch(() => ({}));
    if (!r.ok) {
      console.error('AURAI upstream HTTP status:', r.status);
      return json({ error: r.status === 401 || r.status === 403
        ? 'AURAI model sunucusu kimlik doğrulamasını reddetti. AURAI_API_KEY değerini ve sağlayıcı ayarlarını kontrol et.'
        : r.status === 404
          ? 'AURAI model adresi bulunamadı. AURAI_API_URL değerinin /v1 taban adresi olduğundan ve model sağlayıcısının chat/completions yolunu desteklediğinden emin ol.'
          : r.status === 429
            ? 'AURAI model sunucusunun istek sınırına ulaşıldı. Biraz bekleyip tekrar dene veya model sağlayıcısı kotasını kontrol et.'
            : `AURAI model sunucusu HTTP ${r.status} hatası döndürdü. Edge Function logları ve model sağlayıcısı ayarları kontrol edilmeli.`, code: 'MODEL_UPSTREAM_HTTP', crisis }, 502);
    }
    const answer = String(d?.choices?.[0]?.message?.content || '').trim();
    if (!answer) return json({ error: 'AURAI yanıt alamadı.', crisis }, 502);
    return json({ answer, crisis });
  } catch (e) {
    console.error('aurai-chat upstream error', e);
    const timedOut = e instanceof Error && (e.name === 'TimeoutError' || e.name === 'AbortError');
    return json({ error: timedOut
      ? 'AURAI model sunucusu zamanında yanıt vermedi. Sunucunun açık olduğunu, erişilebilirliğini ve kapasitesini kontrol et.'
      : 'AURAI model sunucusuna bağlanamadı. AURAI_API_URL adresini, sunucu erişimini ve Edge Function loglarını kontrol et.', code: timedOut ? 'MODEL_TIMEOUT' : 'MODEL_CONNECTION_FAILED', crisis }, 502);
  }
});
