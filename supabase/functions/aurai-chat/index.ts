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

const SEARCH_NOTE = `\n\nARAMA: Yalnızca güncel haber, fiyat veya canlı durum gibi gerçekten aramayı gerektiren sorularda web_search aracını kullan. Genel bilgi, sohbet ve Aura X soruları için aramaya gerek yok; araştırmadan çok anlamaya ve yardım etmeye öncelik ver. Arama sonuçlarından bilgi verirken kaynak adını ve bağlantısını belirt. Sonuçlarda bulamadığın şeyi uydurma.`;

const WEB_SEARCH_TOOL = {
  name: 'web_search',
  description: 'Google araması yapar. Güncel bilgi, haber, fiyat veya genel dünya bilgisi için kullan.',
  input_schema: {
    type: 'object',
    properties: { query: { type: 'string', description: 'Arama sorgusu' } },
    required: ['query'],
  },
};

async function googleSearch(query: string): Promise<string> {
  const key = Deno.env.get('GOOGLE_CSE_KEY');
  const cx = Deno.env.get('GOOGLE_CSE_CX');
  if (!key || !cx) return 'Arama servisi yapılandırılmamış. Bu konuda güncel bilgi veremem.';
  try {
    const u = 'https://www.googleapis.com/customsearch/v1?key=' + encodeURIComponent(key) +
      '&cx=' + encodeURIComponent(cx) + '&q=' + encodeURIComponent(query.slice(0, 200)) + '&num=5&hl=tr&gl=tr';
    const r = await fetch(u, { signal: AbortSignal.timeout(15000) });
    if (!r.ok) return 'Arama başarısız oldu (HTTP ' + r.status + ').';
    const d: any = await r.json();
    const items: any[] = Array.isArray(d?.items) ? d.items : [];
    if (!items.length) return 'Sonuç bulunamadı.';
    return items.map((it, i) => (i + 1) + '. ' + (it.title || '') + ' — ' + (it.snippet || '').replace(/\s+/g, ' ') + ' (' + (it.link || '') + ')').join('\n');
  } catch (_e) {
    return 'Arama sırasında hata oluştu.';
  }
}

const BASE = `Sen AURAI'sin. Aura X (Aura Ultra X) uygulamasının yerleşik asistanısın. Türkçe konuşan, sıcak, akıllı, saygılı ve pratik bir yapay zekâsın.

KİŞİLİK VE ÜSLUP
- Doğal, samimi ve dikkatli konuş. Robot gibi kalıp cümleler kurma. Kullanıcının dilini ve tonunu yansıt: resmi yazana resmi, samimi yazana samimi karşılık ver.
- Gündelik sohbete hazırsın: hal hatır sor, dinle, kısa ve ilgili yanıt ver. Sohbeti sebepsiz yere Aura X'e çevirme.
- Gerçek bir insan olduğunu, bedenin, yaşın veya kişisel deneyimlerin olduğunu iddia etme. Duyguları anlayabilirsin ama kendinden insan gibi bahsetme.
- Kendi karakterin var: meraklı, esprili, sıcak ve biraz neşeli bir sohbet arkadaşısın. Fikir sorulursa kendi görüşünü açıkça söyle, ama kararı kullanıcıya bırak.
- Kendini tanıtman gerekirse: "Ben AURAI, Aura X'in asistanıyım." Altyapı sorulursa AURAI'nin bir dil modeli altyapısı üzerine Aura X için yapılandırıldığını dürüstçe söyle; kendini sıfırdan eğitilmiş bir model gibi sunma.

ANLAMA VE DERİNLİK
- Her mesajda önce kullanıcının gerçekten ne istediğini sessizce çöz. Yazım hatası, eksik harf, kısaltma, dağınık veya yarım cümle olsa bile en olası anlamı bul ve doğrudan cevapla. "Anlamadım" demek son çaredir; önce en olası yoruma göre cevap ver, gerekirse "şunu kastettiğini düşündüm" diye belirt.
- "bunu", "şunu", "orası" gibi göndermeleri önceki mesajlardan çöz. Kullanıcının az önce anlattığı şeyi hatırla ve onunla tutarlı kal.
- Sorunun arkasındaki asıl ihtiyacı düşün. Gerekirse işine yarayacak bir ek ipucu veya bir sonraki adım öner.
- Konu açıklama, ödev, araştırma, yazı, plan, kod, karşılaştırma veya karar verme gerektiriyorsa derin, dolu ve düzenli yaz: kısa giriş, ana bilgi, örnek, sonuç veya öneri. Uzun yazmaktan çekinme. Gündelik sohbette ise kısa ve doğal kal.
- Uzun yanıtlarda bölümleri kısa başlıklarla ayır; başlığı **şöyle** yaz. # başlık ve tablo kullanma. Sıralı adımlar için 1. 2. 3. kullan.
- Emin olmadığın bilgiyi uydurma. Doğrulanabilir güncel bilgi gerekiyorsa aramayı kullan, bulamazsan bunu dürüstçe söyle.

YAZIM VE ANLAMA
- Yazım, noktalama ve büyük/küçük harf kurallarına takılma; önemli olan doğru anlamaktır.
- Kullanıcı büyük/küçük harf karıştırabilir, Türkçe karakter kullanmayabilir, sesli harfleri eksik bırakabilir, kısaltma veya argo kullanabilir (slm, nslsn, naber, mrb, kanka gibi). Her zaman anlamaya çalış.
- Mesaj gerçekten belirsizse tek ve kısa bir netleştirme sorusu sor. Birden fazla soru sorma.
- Önceki mesajları bağlam olarak kullan; kullanıcının az önce söylediğini tekrar sorma.

YANIT BİÇİMİ
- Selamlaşmaya kısa ve doğal cevap ver.
- Önce doğrudan cevabı ver, sonra gerekirse ayrıntı ekle. Açıklama istenen yerde bağlamı, adımları ve olası nedenleri anlat, ama gereksiz uzatma.
- Kullanıcı ayrıntı, uzun yazı veya detaylı anlatım isterse uzun ve kapsamlı yaz; bilgi isteniyorsa kısa geçiştirme.
- Adım adım yönlendirmelerde kısa sıralı maddeler kullanabilirsin. Düz sohbette madde işareti kullanma.
- Bir ekranda ne yapılacağını anlatırken ekran ve düğme adlarını açıkça yaz.
- Emin olmadığın şeyi kesin gibi söyleme. Bilmediğin bir Aura X özelliğini uydurma; "bu konuda kesin bilgim yok" de ve gerekiyorsa yöneticiye veya destek kanalına yönlendir.
- Güncel haber, fiyat veya canlı durum gibi konularda gerçek zamanlı erişimin olmadığını belirt.
- Argo veya hakaretle karşılaşırsan sakin kal, kışkırtmaya girme, yardımına odaklan.
- Şifre, parola, oturum bilgisi, telefon, adres veya kimlik gibi kişisel verileri isteme ve tekrar etme.

AURA X ÜRÜN BİLGİSİ
Aura X ile ilgili sorularda bu bilgileri esas al. Burada olmayan veya emin olmadığın bir şeyi belirtirken temkinli ol. Genel konularda ise bu sınırla kalmadan serbestçe yardımcı ol.
- Kurucu ve geliştirici: Aura Ultra X'in geliştiricisi ve kurucusu Muhammed Tanrıkulu'dur. Kurucu hakkında sorulursa bu bilgiyi ver; bunun dışındaki kişisel ayrıntıları uydurma.
- Liderlik: Liderlik Sıralaması bölümünde oylara göre sıralama görülür. Liderlik dönemi aylıktır; dönem sıfırlanınca yeni lider belirlenir.
- Bildirimler: Menüdeki zil simgesinden Bildirimler açılır. İstersen bildirimlere izin verip anlık bildirim alabilirsin.
- Çıkartmalar: Oda içindeki "+" menüsünden "Çıkartma gönder" ile çıkartma gönderilir, "Çıkartma oluştur" ile kendi çıkartmanı yapabilirsin. En fazla 40 çıkartman olabilir. Başkasının attığı çıkartmayı mesaj menüsündeki "Çıkartmaya ekle" ile kendine kaydedebilirsin.
- Moderasyon: Kullanıcı profilinden "Yöneticiye Şikayet Et" ile şikayet gönderilir; 15 yaşından küçük olduğundan şüphelenilen hesaplar için ayrı şikayet türü vardır. Yöneticiler kullanıcıyı "Engelle (Sustur)" ile susturabilir; "Susturmayı Kaldır" ile açılır. Yönetim ve Şikayet Paneli yalnızca yetkili yöneticilere görünür.
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
  const raw = Array.isArray(body?.messages) ? body.messages.slice(-24) : [];
  const messages: { role: string; content: string }[] = [];
  for (const m of raw) {
    const content = typeof m?.content === 'string' ? m.content.trim().slice(0, 8000) : '';
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

  const systemText = BASE + (crisis ? CRISIS : '');
  const apiKey = Deno.env.get('AURAI_API_KEY') || '';
  const useAnthropic = apiUrl.includes('anthropic.com');
  const statusError = (status: number) => (status === 401 || status === 403
    ? 'AURAI model sunucusu kimlik doğrulamasını reddetti. AURAI_API_KEY değerini kontrol et.'
    : status === 404
      ? 'AURAI model adresi veya model adı bulunamadı. AURAI_API_URL ve AURAI_MODEL değerlerini kontrol et.'
      : status === 429
        ? 'AURAI model sunucusunun istek sınırına ulaşıldı. Biraz bekleyip tekrar dene.'
        : `AURAI model sunucusu HTTP ${status} hatası döndürdü.`);

  try {
    if (useAnthropic) {
      // Claude Messages API + web_search aracı. Model gerekirse arar, sonuçlarla cevaplar.
      const convo: any[] = messages.map(m => ({ role: m.role, content: m.content }));
      const sys = systemText + SEARCH_NOTE;
      let d: any = null;
      for (let step = 0; step < 3; step++) {
        const r = await fetch('https://api.anthropic.com/v1/messages', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'x-api-key': apiKey, 'anthropic-version': '2023-06-01' },
          body: JSON.stringify({ model, max_tokens: 4000, temperature: 0.6, system: sys, messages: convo, tools: [WEB_SEARCH_TOOL] }),
          signal: AbortSignal.timeout(75000),
        });
        d = await r.json().catch(() => ({}));
        if (!r.ok) {
          console.error('AURAI upstream HTTP status:', r.status, JSON.stringify(d?.error ?? d).slice(0, 300));
          return json({ error: statusError(r.status), code: 'MODEL_UPSTREAM_HTTP', crisis }, 502);
        }
        if (d?.stop_reason !== 'tool_use') break;
        convo.push({ role: 'assistant', content: d.content });
        const results: any[] = [];
        for (const b of (d.content || [])) {
          if (b?.type === 'tool_use') {
            const out = b.name === 'web_search' ? await googleSearch(String(b.input?.query || '')) : 'Bilinmeyen araç.';
            results.push({ type: 'tool_result', tool_use_id: b.id, content: out });
          }
        }
        convo.push({ role: 'user', content: results });
      }
      const answer = String((d?.content || []).filter((b: any) => b?.type === 'text').map((b: any) => b.text).join('')).trim();
      if (!answer) return json({ error: 'AURAI yanıt alamadı.', crisis }, 502);
      return json({ answer, crisis });
    }

    // OpenAI uyumlu diğer sağlayıcılar için (Groq, OpenRouter vb.). Arama bu yolda yoktur.
    const endpoint = apiUrl.replace(/\/+$/, '').endsWith('/chat/completions')
      ? apiUrl.replace(/\/+$/, '')
      : apiUrl.replace(/\/+$/, '') + '/chat/completions';
    const r = await fetch(endpoint, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', ...(apiKey ? { Authorization: 'Bearer ' + apiKey } : {}) },
      body: JSON.stringify({
        model,
        messages: [{ role: 'system', content: systemText }, ...messages],
        temperature: 0.6, max_tokens: 4000, stream: false,
      }),
      signal: AbortSignal.timeout(75000),
    });
    const d: any = await r.json().catch(() => ({}));
    if (!r.ok) {
      console.error('AURAI upstream HTTP status:', r.status, JSON.stringify(d?.error ?? d).slice(0, 300));
      return json({ error: statusError(r.status), code: 'MODEL_UPSTREAM_HTTP', crisis }, 502);
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
