/* AURAI - AuraX içi yardımcı ve sohbet paneli. Yalnızca giriş yapmış kullanıcıya görünür.
   Yanıt sırası: 1) kriz kontrolü  2) hal hatır  3) Aura X bilgi tabanı (model gerektirmez)
                 4) aurai-chat Edge Function (sunucu modeli)  5) yerel tarayıcı modeli (isteğe bağlı).
   Mevcut kodu değiştirmez; index.html içinde tek satırla yüklenir. */
(function () {
  'use strict';
  if (window.__auraiWidget) return;
  window.__auraiWidget = true;

  // Yerel model (isteğe bağlı, bir kez indirilir). Zayıf cihazda 0.5B modeli kullan.
  const LOCAL_MODEL_ID = 'Qwen2.5-1.5B-Instruct-q4f16_1-MLC';
  const LOCAL_SYSTEM = 'Sen AURAI\'sin: Aura X uygulamasının Türkçe konuşan, sıcak ve yardımsever asistanısın. Yazım hatalarını, eksik sesli harfleri ve küçük harfle yazılan mesajları anlarsın. Gerçek bir insan olduğunu iddia etme. Gerçek zamanlı internet erişimin yoktur. Emin değilsen bunu açıkça söyle. Kısa ve net yaz.';

  // ---------- Metin yardımcıları (yazım toleransı) ----------
  const fold = (s) => String(s || '').toLocaleLowerCase('tr-TR')
    .replace(/ı/g, 'i').replace(/ş/g, 's').replace(/ğ/g, 'g').replace(/ü/g, 'u').replace(/ö/g, 'o').replace(/ç/g, 'c')
    .replace(/[^a-z0-9\s]/g, ' ').replace(/\s+/g, ' ').trim();
  const squeeze = (w) => w.replace(/(.)\1+/g, '$1');
  const skel = (w) => squeeze(w).replace(/[aeiou]/g, '');
  const norm = fold;

  // Bir kelime, bir anahtar kelimeyle eşleşir mi? (ek almış, sesli harfi eksik veya yazımı bozuk olabilir)
  function wordMatches(word, stem) {
    if (word === stem || word.startsWith(stem)) return true;
    // Kısa anahtar kelimeler (3 harf ve altı) yalnızca birebir/başlangıç eşleşmesiyle kabul edilir; yoksa "bu" gibi kelimeler her şeyle eşleşir.
    if (stem.length < 4) return false;
    const sw = skel(word), ss = skel(stem);
    if (ss.length < 3) return false;
    return sw === ss || sw.startsWith(ss);
  }
  // Bir grubun tüm anahtar kelimeleri mesajda var mı?
  const groupMatches = (words, group) => group.every(stem => words.some(w => wordMatches(w, stem)));

  // ---------- Hal hatır ----------
  const SMALLTALK = {
    greet: ['merhaba', 'selam', 'slm', 'mrb', 'sa', 'as', 'hey', 'hello', 'selamlar'],
    greetSkel: ['mrhb', 'slm', 'mrb', 'slmnlkm', 'hlo'],
    how: ['nasilsin', 'naber', 'nbr', 'nasilsiniz', 'iyimisin', 'napiyorsun', 'nabersin'],
    howSkel: ['nslsn', 'nbr', 'nhbr', 'nppsn'],
    bye: ['gorusuruz', 'hosca', 'bay', 'bye', 'gule'],
  };
  function smalltalk(text) {
    const words = norm(text).split(' ').filter(Boolean);
    if (!words.length || words.length > 4) return '';
    const hasG = words.some(w => SMALLTALK.greet.includes(w) || SMALLTALK.greetSkel.includes(skel(w)));
    const hasH = words.some(w => SMALLTALK.how.includes(w) || SMALLTALK.howSkel.includes(skel(w))) || (words.includes('iyi') && words.includes('misin'));
    if (hasG && hasH) return 'Merhaba! İyiyim, teşekkür ederim 😊 Sen nasılsın? Aura X tarafında bir konuda yardım istersen buradayım.';
    if (hasH) return 'İyiyim, teşekkür ederim! 😊 Sen nasılsın? İstersen Aura X hakkında bir şey sorabilirsin.';
    if (hasG) return 'Merhaba! 💜 Ben AURAI. Aura X ile ilgili bir şey sorabilir ya da sohbet edebiliriz. Sen nasılsın?';
    if (words.some(w => SMALLTALK.bye.includes(w))) return 'Görüşmek üzere! Yine bekleriz 💜';
    return '';
  }
  function identity(text) {
    const n = norm(text);
    if (/^(kimsin|sen kimsin|aurai kimsin|ne ise yariyorsun|ne ise yararsin)$/.test(n))
      return 'Ben AURAI’yim 💜 Aura X’in kurulum, kullanım ve sorun giderme yardımcısıyım. Özellikleri anlatabilir, takıldığın yerde adım adım yardım edebilirim.';
    return '';
  }

  // ---------- Aura X bilgi tabanı ----------
  // Her kayıt: groups = anahtar kelime grupları (bir grup tamamen eşleşirse kayıt seçilir), a = yanıt.
  const KB = [
    { groups: [['durum', 'paylas'], ['durum', 'olustur'], ['hikaye', 'paylas'], ['hikaye', 'olustur'], ['durum', 'koy']],
      a: 'Durum paylaşmak için Keşfet’in üstündeki durum şeridinde “Oluştur” kutusuna dokun. Metnini yaz, istersen görsel veya video ekle, sonra “Paylaş”a bas. Durumlar 24 saat görünür; yeni durum paylaşınca öncekinin yerine geçer.\n\nPaylaşamıyorsan ekranda çıkan hata mesajını bana yaz, birlikte bakalım.' },
    { groups: [['mod', 'sec'], ['mod', 'degis'], ['mod', 'ayarla'], ['modu', 'nasil'], ['mod']],
      a: 'Modunu profilinde “Modun” alanından seçebilirsin: profil düzenleme ekranını aç, modunu seç ve kaydet. Mod seçip keşfete gönderi atarsan adının altında küçük bir etiket olarak görünür. Etikete basarsan “Bu kullanıcının modunu gösterir” açıklaması çıkar.' },
    { groups: [['tema'], ['baloncuk'], ['arka', 'plan'], ['seffaf'], ['palet']],
      a: 'Oda içinde başlıktaki palet simgesine dokun. Arka plan olarak sadece uzay temalarından birini seçebilirsin. Şeffaf modu açarsan baloncuklar kapanır ve mesajlar arka planın üstüne yazılır. Şeffaf modu kapalıyken koyu veya açık renk paletinden baloncuk rengi seçebilirsin.\n\nBu ayarlar sadece sana özel ve bu cihazda saklanır.' },
    { groups: [['tepki'], ['emoji', 'tepki'], ['emoji', 'ver'], ['reaksiyon']],
      a: 'Bir mesajın yanındaki gülen yüz simgesine dokun ve bir emoji seç. Her kişi bir mesaja tek tepki verebilir; yeni tepki seçersen öncekinin yerine geçer. Tepkiler odadaki herkese görünür.' },
    { groups: [['oda', 'olustur'], ['oda', 'ac'], ['yeni', 'oda'], ['oda', 'kur']],
      a: 'Odalar bölümünden yeni oda oluşturabilirsin. Oda adını yazıp oluşturduktan sonra odaya girip mesajlaşmaya başlayabilirsin. Özel bir oda kurarsan katılmak isteyenlerin parolayı girmesi gerekir.' },
    { groups: [['oda', 'katil'], ['odaya', 'gir'], ['oda', 'bul']],
      a: 'Odalar bölümünde mevcut odaları görüp katılabilirsin. Özel bir odaya katılmak için oda sahibinin verdiği parolayı girmen gerekir.' },
    { groups: [['sifre'], ['giris', 'yapam'], ['giris', 'sorun'], ['giris', 'olmuyor'], ['unuttum']],
      a: 'Giriş ekranında “Şifremi Unuttum” ile şifreni sıfırlayabilirsin. Giriş yapamıyorsan önce kullanıcı adı ve şifreni kontrol et. Hâlâ olmuyorsa ekrandaki tam hata mesajını bana yaz, birlikte bakalım.' },
    { groups: [['profil', 'duzenle'], ['profil', 'degis'], ['kullanici', 'adi', 'degis'], ['hakkinda', 'yazi']],
      a: 'Profil ekranından adını, hakkında yazısını ve modunu düzenleyebilirsin. Kullanıcı adı değiştirme, aynı adı kullanan bir hesap varsa kabul edilmez.' },
    { groups: [['takip'], ['takipci'], ['kullanici', 'bul'], ['arama']],
      a: 'Kullanıcı Bul bölümünden kişileri arayıp takip edebilirsin. Takip ettiğin kişilerin durumlarını ve gönderilerini görebilirsin.' },
    { groups: [['gonderi', 'paylas'], ['gonderi', 'at'], ['post', 'at'], ['gonderi', 'duzenle'], ['gonderi', 'sil']],
      a: 'Keşfet’teki paylaşım alanından metin, görsel veya video ile gönderi paylaşabilirsin. Kendi gönderini düzenleyebilir veya silebilirsin. Başkalarının gönderilerine beğeni ve yorum yapabilirsin.' },
    { groups: [['cizim'], ['cizim', 'tahta']],
      a: 'Odada “Çizim” düğmesiyle ortak çizim tahtası açılır. Bu özellik oda ayarına bağlıdır; kilitliyse oda yöneticisinden izin istemen gerekir.' },
    { groups: [['youtube'], ['video', 'senkron']],
      a: 'Odalarda senkron YouTube oynatma oda ayarına ve yetkiye bağlıdır. Kilitliyse oda yöneticisinden izin istemen gerekir.' },
    { groups: [['iphone', 'centik'], ['centik'], ['iphone', 'kesik'], ['ust', 'kisim', 'kesik']],
      a: 'Üst kısım çentik alanına göre ayarlandı. Hâlâ kesik görünüyorsa sayfayı yenile ve Safari veya Chrome’u güncelle. Ekran görüntüsüyle bana bildirirsen hatayı birlikte inceleyebiliriz.' },
    { groups: [['aura', 'nedir'], ['aura', 'x', 'ne'], ['bu', 'uygulama', 'ne']],
      a: 'Aura X bir sosyal ağ uygulamasıdır. Profil, Keşfet akışı, gönderiler, 24 saatlik durumlar, takip, odalar ve mesajlaşma özellikleri vardır.' },
    { groups: [['oy', 'ver'], ['oy', 'nasil'], ['liderlik']],
      a: 'Bir kullanıcıya gönderisindeki “Oy Ver” düğmesiyle oy verebilirsin. Oy sayıları liderlik tablosunu etkiler.' },
  ];
  function kbAnswer(text) {
    const words = norm(text).split(' ').filter(Boolean);
    if (!words.length) return '';
    for (const entry of KB) {
      if (entry.groups.some(g => groupMatches(words, g))) return entry.a;
    }
    return '';
  }
  const FALLBACK_HELP = 'Bu konuda net bir bilgim yok. Ne yapmak istediğini biraz daha açıklar mısın? Örneğin: durum paylaşma, mod seçme, tema değiştirme, emoji tepkisi, şifre sıfırlama, oda oluşturma gibi konularda yardımcı olabilirim.';

  // Test ve hata ayıklama için (yalnızca okuma).
  window.__auraiLogic = { fold, skel, smalltalk, identity, kbAnswer };

  // ---------- Arayüz ----------
  const CRISIS_RE = /\b(intihar|kendimi oldur\w*|kendime zarar|canima kiy\w*|yasamak istemiyorum|olmek istiyorum|hayatima son|kendimi as\w*|kendimi atac\w*|kendimi kes\w*|artik yasayamam)\b/;
  const EMERGENCY_RE = /\b(nefes alamiyorum|nefes alamiyor|kalp krizi|bilinci kapali|bayildi|agir kaza|trafik kazasi|yangin cikti|evde yangin|saldiriya ugr|ciddi yarali|ambulans lazim|acil yardim lazim|canim tehlikede)\b/;

  const el = (tag, cls, text) => { const n = document.createElement(tag); if (cls) n.className = cls; if (text !== undefined) n.textContent = text; return n; };

  const style = el('style');
  style.textContent = `
  #auraiFab{position:fixed;right:14px;bottom:calc(88px + env(safe-area-inset-bottom,0px));z-index:9998;display:none;align-items:center;gap:6px;padding:11px 15px;border:0;border-radius:999px;color:#fff;font-weight:800;font-size:14px;cursor:pointer;background:linear-gradient(135deg,var(--primary,#8b5cf6),var(--accent,#ec4899));box-shadow:0 6px 22px #0008}
  #auraiPanel{position:fixed;z-index:9999;right:0;bottom:0;width:100%;height:78vh;max-height:100dvh;display:none;flex-direction:column;background:var(--bg-surface,#121216);color:#f4f4f8;border:1px solid #ffffff1a;border-radius:18px 18px 0 0;box-shadow:0 -10px 40px #000a;padding-bottom:env(safe-area-inset-bottom,0px)}
  #auraiPanel.open{display:flex}
  @media(min-width:700px){#auraiPanel{right:18px;bottom:18px;width:390px;height:560px;border-radius:18px}}
  #auraiHead{display:flex;align-items:center;gap:8px;padding:12px 14px;border-bottom:1px solid #ffffff14}
  #auraiHead b{flex:1;font-size:15px;letter-spacing:1px}
  #auraiHead button{border:1px solid #ffffff22;background:transparent;color:#ddd;border-radius:9px;padding:6px 9px;font-size:12px;cursor:pointer}
  #auraiLog{flex:1;overflow:auto;padding:14px;display:flex;flex-direction:column;gap:10px}
  .auraiMsg{max-width:88%;padding:10px 12px;border-radius:14px;font-size:14px;line-height:1.55;white-space:pre-wrap;overflow-wrap:anywhere;background:var(--bg-surface-hover,#1a1a20);border:1px solid #ffffff14}
  .auraiMsg.me{align-self:flex-end;background:var(--primary,#8b5cf6);border-color:transparent}
  .auraiMsg.err{color:#ffabb3}
  .auraiCall{display:block;margin-top:10px;padding:13px;border-radius:12px;background:linear-gradient(135deg,#21c55d,#15803d);color:#fff;text-align:center;font-weight:900;text-decoration:none;box-shadow:0 4px 14px #16a34a44}
  .auraiBtn{display:block;margin-top:10px;padding:11px;width:100%;border:0;border-radius:12px;background:linear-gradient(135deg,var(--primary,#8b5cf6),var(--accent,#ec4899));color:#fff;font-weight:800;cursor:pointer}
  #auraiForm{display:flex;gap:8px;padding:10px 12px;border-top:1px solid #ffffff14}
  #auraiIn{flex:1;resize:none;max-height:110px;padding:10px 12px;border-radius:12px;border:1px solid #ffffff22;background:var(--bg-base,#050507);color:#fff;font-size:16px;font-family:inherit}
  #auraiSend{border:0;border-radius:12px;padding:0 15px;color:#fff;font-size:18px;cursor:pointer;background:linear-gradient(135deg,var(--primary,#8b5cf6),var(--accent,#ec4899))}
  #auraiSend:disabled{opacity:.45}`;
  document.head.appendChild(style);

  const fab = el('button', '', '✨ AURAI'); fab.id = 'auraiFab'; fab.type = 'button';
  const panel = el('div'); panel.id = 'auraiPanel';
  const head = el('div'); head.id = 'auraiHead';
  const title = el('b', '', 'AURAI · Destek + Sohbet');
  const closeBtn = el('button', '', '✕'); closeBtn.type = 'button';
  head.append(title, closeBtn);
  const log = el('div'); log.id = 'auraiLog';
  const form = el('form'); form.id = 'auraiForm';
  const input = el('textarea'); input.id = 'auraiIn'; input.rows = 1; input.maxLength = 2000; input.placeholder = 'Bir şey sor veya sohbet edelim…';
  const send = el('button', '', '↑'); send.id = 'auraiSend'; send.type = 'submit';
  form.append(input, send);
  panel.append(head, log, form);
  document.body.append(fab, panel);

  let msgs = [], busy = false;
  let localEngine = null, localLoading = false;
  const sb = () => window.supabaseClient;

  function add(text, cls) { const m = el('div', 'auraiMsg' + (cls ? ' ' + cls : ''), text); log.append(m); log.scrollTop = log.scrollHeight; return m; }
  function crisisCard() {
    const m = add('Seni ciddiye alıyorum. Eğer şu an senin ya da başka birinin güvenliği yakın tehlikedeyse Türkiye’de 112 Acil Çağrı Merkezi’ni ara. Aşağıdaki yeşil düğmeye sen basmalısın; ben telefonunda kendiliğimden arama başlatamam. Yanında güvenilir biri varsa hemen ona da haber ver. Buradayım, yazmaya devam edebilirsin.');
    m.dataset.auraiEmergency = 'true';
    const a = el('a', 'auraiCall', '📞 112’yi ara'); a.href = 'tel:112'; a.setAttribute('aria-label', 'Telefon uygulamasında 112 aramasını başlat'); m.append(a);
  }
  function offerLocalModel() {
    if (localEngine || localLoading) return;
    const b = el('button', 'auraiBtn', '🧠 Genel sohbet için yerel AURAI modelini yükle (~1 GB, bir kere)');
    b.type = 'button';
    b.onclick = () => { b.remove(); loadLocalModel(); };
    log.append(b); log.scrollTop = log.scrollHeight;
  }
  async function loadLocalModel() {
    if (!navigator.gpu) { add('Bu tarayıcıda WebGPU yok. Masaüstü veya Android’de güncel Google Chrome ile tekrar dene.', 'err'); return; }
    localLoading = true;
    const status = add('Yerel model indiriliyor… (ilk seferde biraz sürer)');
    try {
      const webllm = await import('https://esm.run/@mlc-ai/web-llm');
      localEngine = await webllm.CreateMLCEngine(LOCAL_MODEL_ID, {
        initProgressCallback: (p) => { status.textContent = 'Yerel model indiriliyor… %' + Math.round((p.progress || 0) * 100); },
      });
      status.textContent = 'Yerel AURAI modeli hazır. Artık genel sohbet edebiliriz 💜';
    } catch (err) {
      console.error('Yerel model yüklenemedi:', err);
      status.textContent = 'Yerel model yüklenemedi: ' + (err.message || err);
      status.classList.add('err');
    } finally { localLoading = false; }
  }
  async function localAnswer(q) {
    const history = [{ role: 'system', content: LOCAL_SYSTEM }, ...msgs.slice(-12)];
    const r = await localEngine.chat.completions.create({ messages: history, temperature: 0.7, max_tokens: 600 });
    return String(r.choices?.[0]?.message?.content || '').trim();
  }

  add('Merhaba! Ben AURAI 💜 Aura X kurulum, kullanım ve hata çözümünde yardımcı olurum; istersen sohbet de edebiliriz. Bir şey takılırsa beraber adım adım bakalım. 😊');

  fab.onclick = () => { panel.classList.add('open'); fab.style.display = 'none'; input.focus(); };
  closeBtn.onclick = () => { panel.classList.remove('open'); refreshFab(); };
  input.addEventListener('input', () => { input.style.height = 'auto'; input.style.height = Math.min(input.scrollHeight, 110) + 'px'; });
  input.addEventListener('keydown', (e) => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); form.requestSubmit(); } });

  function reply(text) {
    add(text);
    msgs.push({ role: 'assistant', content: text });
    msgs = msgs.slice(-16);
  }

  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    const q = input.value.trim();
    if (!q || busy) return;
    busy = true; send.disabled = true; input.value = ''; input.style.height = 'auto';
    add(q, 'me'); msgs.push({ role: 'user', content: q });
    msgs = msgs.slice(-16);
    try {
      const n = norm(q);
      const localCrisis = CRISIS_RE.test(n) || EMERGENCY_RE.test(n);
      if (localCrisis) { crisisCard(); return; }

      const quick = identity(q) || smalltalk(q);
      if (quick) { reply(quick); return; }

      // Öncelik: sunucu modeli (en iyi yanıt). Model kullanılamazsa bilgi tabanı, sonra yerel model.
      const client = sb();
      if (client) {
        const pending = add('Biraz düşünüyorum…');
        try {
          const { data, error } = await client.functions.invoke('aurai-chat', { body: { messages: msgs.slice(-16), mode: 'assistant' } });
          let d = data;
          if (error) { try { d = await error.context.json(); } catch (_) { d = null; } }
          if (d && d.crisis) crisisCard();
          if (d && d.answer) {
            pending.textContent = d.answer;
            msgs.push({ role: 'assistant', content: d.answer });
            msgs = msgs.slice(-16);
            return;
          }
          throw new Error((d && d.error) || 'AURAI sunucu modeline ulaşamadı.');
        } catch (err) {
          pending.remove();
          console.warn('AURAI sunucu modeli yanıt vermedi:', err && err.message);
        }
      }

      const kb = kbAnswer(q);
      if (kb) { reply(kb); return; }

      if (localEngine) { reply(await localAnswer(q)); return; }

      reply(FALLBACK_HELP);
      offerLocalModel();
    } catch (err) {
      console.error('AURAI hatası:', err);
      add('Bir hata oluştu: ' + (err.message || err), 'err');
    } finally {
      busy = false; send.disabled = false; log.scrollTop = log.scrollHeight; input.focus();
    }
  });

  // Yalnızca giriş yapmış kullanıcıya göster.
  let signedIn = false;
  function refreshFab() { fab.style.display = signedIn && !panel.classList.contains('open') ? 'inline-flex' : 'none'; if (!signedIn) panel.classList.remove('open'); }
  function watch() {
    const c = sb(); if (!c) return setTimeout(watch, 400);
    c.auth.getSession().then(({ data }) => { signedIn = !!(data && data.session); refreshFab(); });
    c.auth.onAuthStateChange((_ev, session) => { signedIn = !!session; if (!signedIn) { msgs = []; } refreshFab(); });
  }
  watch();
})();
