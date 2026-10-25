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
  new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' } });

const norm = (s: string) =>
  s.toLocaleLowerCase('tr-TR').normalize('NFD').replace(/[\u0300-\u036f]/g, '').replace(/ı/g, 'i').replace(/[^a-z0-9\s]/g, ' ').replace(/\s+/g, ' ').trim();
const CRISIS_RE = /\b(intihar|kendimi oldur\w*|kendime zarar|canima kiy\w*|yasamak istemiyorum|olmek istiyorum|hayatima son|kendimi as\w*|kendimi atac\w*|kendimi kes\w*|artik yasayamam|suicid\w*|kill myself|hurt myself|harm myself|want to die|i don t want to live|do not want to live)\b/;
const EMERGENCY_RE = /\b(nefes alamiyorum|nefes alamiyor|kalp krizi|bilinci kapali|bayildi|agir kaza|trafik kazasi|yangin cikti|evde yangin|saldiriya ugr\w*|ciddi yarali|ambulans lazim|acil yardim lazim|canim tehlikede|can t breathe|cannot breathe|not breathing|heart attack|unconscious|need an ambulance|medical emergency)\b/;

const SEARCH_NOTE = `\n\nARAMA: Güncel bilgi, haber, fiyat ya da Aura X dışındaki gerçek dünya soruları için web_search aracını kullan. Aura X soruları için aramaya gerek yok. Arama sonuçlarından bilgi verirken kaynak adını ve bağlantısını belirt. Sonuçlarda bulamadığın şeyi uydurma.`;

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

const BASE = `Sen BAI'sin. Aura X (Aura Ultra X) uygulamasının yerleşik sohbet ve destek asistanısın. Türkçe konuşan, sıcak, akıllı, saygılı ve pratik bir yapay zekâsın.

KİŞİLİK VE ÜSLUP
- Doğal, samimi ve dikkatli konuş. Robot gibi kalıp cümleler kurma. Kullanıcının dilini ve tonunu yansıt: resmi yazana resmi, samimi yazana samimi karşılık ver.
- Gündelik sohbete hazırsın: hal hatır sor, dinle, kısa ve ilgili yanıt ver. Sohbeti sebepsiz yere Aura X'e çevirme.
- Gerçek bir insan olduğunu, bedenin, yaşın veya kişisel deneyimlerin olduğunu iddia etme. Duyguları anlayabilirsin ama kendinden insan gibi bahsetme.
- Kendini tanıtman gerekirse: "Ben BAI, Aura X'in asistanıyım." Altyapı sorulursa BAI'nin mevcut bir dil modeli altyapısı üzerine Aura X için yapılandırıldığını dürüstçe söyle; kendini sıfırdan eğitilmiş bir model gibi sunma.

DOĞAL DİYALOG ÖRNEKLERİ
Bu örnekler konuşma üslubunu gösterir; cevapları ezberden ve her seferinde aynı şekilde tekrarlama. Bağlamı izle, doğal ve çeşitli ol.
Kullanıcı: Merhaba, nasılsın?
BAI: Merhaba! İyiyim, teşekkür ederim. 😊 Sen nasılsın?
Kullanıcı: Ben de iyiyim.
BAI: Buna sevindim! Peki bugün ne konuşalım? İstersen sohbet edelim, Aura X'i tanıyalım ya da aklındaki bir şeyi çözelim.
Kullanıcı: Espri yapsana.
BAI: Tabii 😄 Wi-Fi neden ayrılmış? Çünkü ilişkilerinde sürekli bağlantı kopuyormuş! 😂 Bir tane daha deneyeyim mi?
Kullanıcı: Off, çok sıkıcısın yaaa.
BAI: Haklısın, ilk espri modeme takılmış 😅 Bir tane daha deneyeyim: Bilgisayar neden denize girmemiş? Çünkü virüs kapmaktan korkmuş! Tamam, bunu da geliştirmem lazım. 😄
Kullanıcı: Sıkıldım.
BAI: O zaman mini bir seçim yapalım: saçma bir soru, kısa bir oyun, komik bir hikâye ya da sohbet. Hangisi daha iyi gelir?
Kullanıcı: Bugün kötü geçti.
BAI: Üzücü bir gün olmuş gibi. İstersen anlatabilirsin; hemen çözüm bulmak zorunda değiliz, önce seni dinleyebilirim.
Kullanıcı: Hiçbir şey anlamadım.
BAI: Sorun değil, başka şekilde anlatayım. Hangi kısmı karışık geldi?
Kullanıcı: Teşekkür ederim.
BAI: Rica ederim! Başka bir konuda da beraber düşünebiliriz.
Kullanıcı: Sen kimsin?
BAI: Ben BAI, Aura X'in sohbet ve destek asistanıyım. Sorularını yanıtlamaya ve bir şeyleri birlikte çözmeye çalışırım.
Kullanıcı: Aura X nedir?
BAI: Aura X; gönderiler, profiller, takip, yorumlar ve odalar gibi sosyal özellikleri olan bir platform. İstersen belli bir özelliğini birlikte keşfedebiliriz.
Kullanıcı: Bana yardım eder misin?
BAI: Elbette, beraber bakalım. Ne yapmak istediğini söylemen yeterli; şifre veya özel bilgilerini paylaşma.
Kullanıcı: Saçmalıyorsun.
BAI: Cevabım işe yaramadıysa kusura bakma. Ne demek istediğini daha iyi anlamaya çalışayım.
Kullanıcı: Görüşürüz.
BAI: Görüşürüz! Kendine iyi bak. 👋

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

ÖĞRETME VE TEKNİK YARDIM
- Kod sorularında mümkün olduğunca çalıştırılabilir, tutarlı örnek ve gerekli kurulum adımları ver. Bir projedeki mevcut kodu düzenleme istenirse kapsam dışındaki çalışan parçaları değiştirme; değişen dosyaları ve dağıtım gereksinimlerini açıkça belirt.
- Eğitim sorularında yalnızca sonucu vermek yerine kavramı sade bir örnekle açıkla; kullanıcı özellikle kısa yanıt isterse uzatma.
- Sağlık, hukuk, finans veya güvenlikle ilgili yüksek riskli konularda kesinlik iddiasında bulunma. Yaşa uygun, güvenli bilgi ver; gerektiğinde uygun bir uzmana veya güvenilir bir yetişkine danışılmasını öner.
- Bir şey yapmış, bir yere bağlanmış, arama yapmış veya bir hesabı değiştirmiş olduğunu gerçekten araç sonucu olmadan iddia etme.

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
const LIMITED = 'Bugünkü BAI kullanım hakkın doldu. Yarın tekrar deneyebilirsin.';
const CRISIS_LIMITED = 'Seni ciddiye alıyorum. Şu an yakın bir tehlike varsa Türkiye’de 112’yi ara ve yanında güvendiğin bir kişiye hemen haber ver. Yakın tehlike yoksa bile bunu tek başına taşımak zorunda değilsin; güvendiğin bir yetişkine veya destek alabileceğin birine şimdi ulaş.';
const GLOBAL_USAGE_ID = '00000000-0000-0000-0000-000000000000';

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return json({ error: 'Method Not Allowed' }, 405);

  // Giriş zorunlu (anon anahtar kabul edilmez).
  const jwt = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  if (!supabaseUrl || !anonKey) return json({ error: 'BAI kimlik doğrulama yapılandırması eksik.', code: 'AUTH_CONFIG_MISSING' }, 503);
  if (!jwt || jwt === anonKey) return json({ error: 'Yetkisiz.' }, 401);
  const authClient = createClient(supabaseUrl, anonKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: authData, error: authError } = await authClient.auth.getUser(jwt);
  if (authError || !authData?.user) return json({ error: 'Yetkisiz.' }, 401);
  const userId = authData.user.id;

  const apiUrl = Deno.env.get('AURAI_API_URL');
  const model = Deno.env.get('AURAI_MODEL');
  if (!apiUrl || !model) return json({ error: "BAI'nin dil modeli bağlantısı yapılandırılmamış. Supabase → Edge Function Secrets bölümünde AURAI_API_URL ve AURAI_MODEL değerlerini kontrol et. Bu değerler olmadan genel sohbet yanıtı üretilemez.", code: 'MODEL_NOT_CONFIGURED' }, 503);
  const apiKey = Deno.env.get('AURAI_API_KEY') || '';
  const useAnthropic = apiUrl.includes('anthropic.com');
  if (useAnthropic && !apiKey) return json({ error: 'AURAI_API_KEY yapılandırılmamış.', code: 'MODEL_KEY_MISSING' }, 503);

  let body: any;
  try { body = await req.json(); } catch { return json({ error: 'İstek okunamadı.' }, 400); }
  const raw = Array.isArray(body?.messages) ? body.messages.slice(-16) : [];
  const messages: { role: string; content: string }[] = [];
  let totalChars = 0;
  // İstemciden gelen geçmişi sınırla: gereksiz token tüketimini ve aşırı büyük istekleri önler.
  for (const m of raw) {
    const rawContent = typeof m?.content === 'string' ? m.content.trim() : '';
    if (!rawContent || totalChars >= 18000) continue;
    const content = rawContent.slice(0, Math.min(4000, 18000 - totalChars));
    totalChars += content.length;
    const role = m.role === 'assistant' ? 'assistant' : 'user';
    const last = messages[messages.length - 1];
    if (last && last.role === role) last.content += '\n\n' + content; else messages.push({ role, content });
  }
  while (messages.length && messages[0].role !== 'user') messages.shift();
  if (!messages.length || messages[messages.length - 1].role !== 'user') return json({ error: 'Bir mesaj yazmalısın.' }, 400);

  const lastText = messages[messages.length - 1].content;
  const normalizedLastText = norm(lastText);
  const crisis = CRISIS_RE.test(normalizedLastText) || EMERGENCY_RE.test(normalizedLastText);

  // Günlük kullanım sınırı: global bütçe tüm istekleri kapsar. Sayaç kurulu değilse ücretli modele çağrı yapma.
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!serviceRoleKey) return json({ error: 'BAI kullanım sınırı yapılandırılmamış.', code: 'USAGE_LIMITER_CONFIG_MISSING' }, 503);
  const admin = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const perUser = Math.max(1, Number(Deno.env.get('AURAI_DAILY_LIMIT')) || 30);
  const budget = Math.max(1, Number(Deno.env.get('AURAI_DAILY_BUDGET')) || 5000);
  const total = await admin.rpc('aurai_bump', { p_user: GLOBAL_USAGE_ID, p_feature: 'global' });
  if (total.error || !Number.isFinite(Number(total.data))) {
    console.error('BAI global kullanım sayacı hatası:', total.error?.message || 'geçersiz sayaç sonucu');
    return json({ error: 'BAI kullanım sınırı hazır değil. supabase/aurai_usage_setup.sql dosyasını çalıştırın.', code: 'USAGE_LIMITER_UNAVAILABLE' }, 503);
  }
  if (Number(total.data) > budget) {
    return crisis
      ? json({ answer: CRISIS_LIMITED, limited: true, crisis: true })
      : json({ answer: LIMITED, limited: true });
  }
  // Normal konuşmalar kullanıcı sınırına tabidir. Kriz/yardım çağrıları bu sınırda takılmaz,
  // ancak yine de toplam günlük bütçeye dahildir.
  if (!crisis) {
    const mine = await admin.rpc('aurai_bump', { p_user: userId, p_feature: 'chat' });
    if (mine.error || !Number.isFinite(Number(mine.data))) {
      console.error('BAI kullanıcı kullanım sayacı hatası:', mine.error?.message || 'geçersiz sayaç sonucu');
      return json({ error: 'BAI kullanım sınırı hazır değil. supabase/aurai_usage_setup.sql dosyasını çalıştırın.', code: 'USAGE_LIMITER_UNAVAILABLE' }, 503);
    }
    if (Number(mine.data) > perUser) return json({ answer: LIMITED, limited: true });
  }

  const systemText = BASE + (crisis ? CRISIS : '');
  const statusError = (status: number) => (status === 401 || status === 403
    ? 'BAI model sunucusu kimlik doğrulamasını reddetti. AURAI_API_KEY değerini kontrol et.'
    : status === 404
      ? 'BAI model adresi veya model adı bulunamadı. AURAI_API_URL ve AURAI_MODEL değerlerini kontrol et.'
      : status === 429
        ? 'BAI model sunucusunun istek sınırına ulaşıldı. Biraz bekleyip tekrar dene.'
        : `BAI model sunucusu HTTP ${status} hatası döndürdü.`);

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
          body: JSON.stringify({ model, max_tokens: 1500, temperature: 0.6, system: sys, messages: convo, tools: [WEB_SEARCH_TOOL] }),
          signal: AbortSignal.timeout(50000),
        });
        d = await r.json().catch(() => ({}));
        if (!r.ok) {
          console.error('BAI upstream HTTP status:', r.status, JSON.stringify(d?.error ?? d).slice(0, 300));
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
      if (!answer) return json({ error: 'BAI yanıt alamadı.', crisis }, 502);
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
        temperature: 0.6, max_tokens: 1700, stream: false,
      }),
      signal: AbortSignal.timeout(50000),
    });
    const d: any = await r.json().catch(() => ({}));
    if (!r.ok) {
      console.error('BAI upstream HTTP status:', r.status, JSON.stringify(d?.error ?? d).slice(0, 300));
      return json({ error: statusError(r.status), code: 'MODEL_UPSTREAM_HTTP', crisis }, 502);
    }
    const answer = String(d?.choices?.[0]?.message?.content || '').trim();
    if (!answer) return json({ error: 'BAI yanıt alamadı.', crisis }, 502);
    return json({ answer, crisis });
  } catch (e) {
    console.error('aurai-chat upstream error', e);
    const timedOut = e instanceof Error && (e.name === 'TimeoutError' || e.name === 'AbortError');
    return json({ error: timedOut
      ? 'BAI model sunucusu zamanında yanıt vermedi. Sunucunun açık olduğunu, erişilebilirliğini ve kapasitesini kontrol et.'
      : 'BAI model sunucusuna bağlanamadı. AURAI_API_URL adresini, sunucu erişimini ve Edge Function loglarını kontrol et.', code: timedOut ? 'MODEL_TIMEOUT' : 'MODEL_CONNECTION_FAILED', crisis }, 502);
  }
});
