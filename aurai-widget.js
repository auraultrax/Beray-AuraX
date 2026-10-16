/* AURAI — Aura X içinde destek ve genel sohbet yardımcısı.
   Öncelik: güvenlik > kısa yanıtlar > Aura X bilgi tabanı > sunucu modeli > isteğe bağlı yerel model.
   Kullanıcı sohbetleri tarayıcıda kalıcı olarak saklanmaz. */
(function () {
  'use strict';
  if (window.__auraiWidget) return;
  window.__auraiWidget = true;

  // Cihaz belleği düşükse daha küçük modeli seç; bellek bilgisi yoksa güvenli tarafta kal.
  const deviceMemory = Number(navigator.deviceMemory || 0);
  const lowResourceDevice = !deviceMemory || deviceMemory <= 4;
  const LOCAL_MODEL_ID = lowResourceDevice ? 'Qwen2.5-0.5B-Instruct-q4f16_1-MLC' : 'Qwen2.5-1.5B-Instruct-q4f16_1-MLC';
  const LOCAL_MODEL_SIZE = lowResourceDevice ? 'yaklaşık 1 GB' : 'yaklaşık 1,6 GB';
  const LOCAL_SYSTEM = 'Sen AURAI\'sin: Türkçe konuşan, sıcak, dikkatli ve yardımsever bir yapay zekâ asistanısın. Kullanıcının diline ve tonuna uyum sağla. Gerçek bir insan olduğunu iddia etme. Güncel internete erişimin yoksa bunu açıkça söyle. Emin olmadığın bilgiyi uydurma. Aura X ile ilgili ürün bilgisinde verilen bilgi tabanına sadık kal. Eğitim sorularını anlaşılır şekilde açıkla; kod yardımı verirken tutarlı, uygulanabilir örnek sun. Parola, oturum anahtarı veya kimlik bilgisi isteme. Hassas konularda yaşa uygun ve güvenli yanıt ver. Gerektiğinde adım adım anlat, gereksiz uzatma.';

  // ---------- Türkçe metin normalleştirme ve yazım toleransı ----------
  const fold = (s) => String(s || '').toLocaleLowerCase('tr-TR')
    .replace(/ı/g, 'i').replace(/[ş]/g, 's').replace(/ğ/g, 'g').replace(/ü/g, 'u').replace(/ö/g, 'o').replace(/ç/g, 'c')
    .replace(/[^a-z0-9\s]/g, ' ').replace(/\s+/g, ' ').trim();
  const squeeze = (w) => w.replace(/(.)\1+/g, '$1');
  const skel = (w) => squeeze(w).replace(/[aeiou]/g, '');
  const norm = fold;

  function wordMatches(word, stem) {
    if (word === stem) return true;
    // Kısa kökleri (mod, oda, oy vb.) çok geniş eşleştirmemek için yalnızca bilinen Türkçe ekleri kabul et.
    if (stem.length <= 3) {
      const shortSuffixes = '(?:lar|ler|lari|leri|larin|lerin|lara|lere|da|de|dan|den|ta|te|tan|ten|ya|ye|yi|yu|yü|i|u|ü|si|sı|su|sü|im|um|üm|m|n|miz|mız|muz|müz|daki|deki)?';
      return new RegExp('^' + stem + shortSuffixes + '$').test(word);
    }
    if (word.startsWith(stem)) return true;
    const sw = skel(word), ss = skel(stem);
    if (ss.length < 3) return false;
    return sw === ss || sw.startsWith(ss);
  }
  const groupMatches = (words, group) => group.every(stem => words.some(w => wordMatches(w, stem)));

  // ---------- Selamlaşma ve kimlik ----------
  const SMALLTALK = {
    greet: ['merhaba', 'selam', 'slm', 'mrb', 'sa', 'as', 'hey', 'hello', 'selamlar', 'gunaydin', 'iyiaksamlar', 'iyiaksamlar', 'iyi geceler', 'selamun', 'aleykum', 'saol', 'naberr'],
    greetSkel: ['mrhb', 'slm', 'mrb', 'slmnlkm', 'hlo', 'gnaydn'],
    how: ['nasilsin', 'naber', 'nbr', 'nasilsiniz', 'iyimisin', 'napiyorsun', 'nabersin', 'nehaber', 'nasilsiniz', 'nevarneyok', 'napiyon', 'napiyosun'],
    howSkel: ['nslsn', 'nbr', 'nhbr', 'nppsn'],
    bye: ['gorusuruz', 'hosca', 'bay', 'bye', 'gule', 'kendineiyi bak', 'iyi geceler'],
    thanks: ['tesekkur', 'tesekkurler', 'sagol', 'saol', 'eyvallah', 'varol', 'cok sagol', 'cok tesekkur'],
  };
  function smalltalk(text) {
    const words = norm(text).split(' ').filter(Boolean);
    if (!words.length || words.length > 8) return '';
    const phrase = norm(text);
    const hasG = words.some(w => SMALLTALK.greet.includes(w) || SMALLTALK.greetSkel.includes(skel(w))) || /selamun aleykum|iyi aksaml|iyi geceler|gunaydin/.test(phrase);
    const hasH = words.some(w => SMALLTALK.how.includes(w) || SMALLTALK.howSkel.includes(skel(w))) || (words.includes('iyi') && words.includes('misin'));
    const hasThanks = words.some(w => SMALLTALK.thanks.includes(w) || w.startsWith('tesekkur') || w.startsWith('sagol')) || /cok sag ?ol|sag ?ol|tesekkur ederim/.test(phrase);
    if (hasThanks) return 'Rica ederim! 💜 Ben buradayım; ister sohbet edelim ister Aura X’te bir şeyi birlikte çözelim. 😊';
    if (hasG && hasH) return 'Merhaba! 😊 Ben AURAI, buradayım ve hazırım. Sen nasılsın? İstersen biraz sohbet edelim ya da aklındaki şeyi birlikte çözelim.';
    if (hasH) return 'İyiyim, teşekkür ederim! 💜 Sen nasılsın? Bugün neler oluyor, nasıl yardımcı olayım?';
    if (hasG) return 'Merhaba! 💜 Ben AURAI. Aura X hakkında yardım edebilirim, bir sorunu adım adım çözebiliriz ya da biraz sohbet edebiliriz. Nasılsın?';
    if (words.some(w => SMALLTALK.bye.includes(w)) || /gorusuruz|hosca kal|kendine iyi bak/.test(phrase)) return 'Görüşmek üzere! 💜 Kendine iyi bak; yardıma ihtiyacın olursa tekrar yazabilirsin. 👋';
    if (/^(iyim|iyiyim|iyidir|fena degil|super|harika|kotu degil)$/.test(phrase)) return 'Buna sevindim! 😄 Bugün ne yapıyoruz: sohbet mi, Aura X’le ilgili bir şey mi, yoksa başka bir konu mu?';
    return '';
  }
  function identity(text) {
    const n = norm(text);
    if (/^(kimsin|sen kimsin|aurai kimsin|ne ise yariyorsun|ne ise yararsin|sen nesin)$/.test(n))
      return 'Ben AURAI’yim 💜 Aura X’in destek ve sohbet asistanıyım. Uygulamanın özelliklerini anlatabilir, hata ayıklamada yardımcı olabilir ve genel sorularını yanıtlamaya çalışabilirim. Emin olmadığım konularda bunu açıkça söylerim.';
    return '';
  }

  // ---------- Aura X ürün bilgi tabanı ----------
  const KB = [
    { groups: [['hesap', 'sil'], ['hesabimi', 'sil'], ['hesabimi', 'silem'], ['hesabim', 'silin'], ['hesap', 'kapat']],
      a: 'Hesabı silmek için Profilim → Hesabımı Sil bölümünü açıp onayı ver ve istenirse mevcut şifrenle doğrula. Silme işlemi için Supabase projesinde `delete-account` Edge Function yayımlanmış ve `SUPABASE_SERVICE_ROLE_KEY` sunucu secret’ı tanımlı olmalı. “Function not found” hatası alıyorsan bu fonksiyon henüz deploy edilmemiştir; parola veya gizli anahtarını kimseyle paylaşma.' },
    { groups: [['bildirim'], ['push'], ['bildirim', 'gelmiyor'], ['bildirim', 'uygulama', 'disinda']],
      a: 'Uygulama dışı bildirimler için tarayıcı/cihaz bildirim iznini açman ve Aura X’i HTTPS üzerinden kullanman gerekir. Android/Chrome’da bildirim izni ver; iPhone’da uygulamayı Ana Ekrana ekleyip oradan aç. Sunucuda `push-notify` Edge Function’ı yayımlanmalı ve Web Push VAPID public/private anahtarları eşleşmelidir. Sadece izin vermek tek başına kapalı uygulamaya push göndermeye yetmez.' },
    { groups: [['mesaj', 'saat'], ['mesaj', 'tarih'], ['tarih', 'saat', 'mesaj'], ['mesaj', 'zaman']],
      a: 'Oda mesajlarında tarih ve saat mesajın gönderildiği anın zaman damgasından gösterilir. Eski mesajlarda zaman damgası kaydedilmemişse saat kesin olarak belirlenemez; yeni mesajlar için tarih ayıracı ve saat görünür.' },
    { groups: [['ozel', 'mesaj'], ['kisinin', 'mesaj'], ['kisiye', 'mesaj'], ['mesaj', 'ozel']],
      a: 'Odada kişiye özel mesaj göndermek için başlıktaki “Özel Bildirimler” bölümünü aç. “Tümü” gelen mesajları listeler; bir kişinin adıyla açılan sekmede yalnızca o kişiyle konuşma görünür. Sekmeye girince o kişiden gelen okunmamış mesajlar okundu işaretlenir.' },
    { groups: [['emoji', 'birlestir'], ['emojileri', 'birlestir'], ['emoji', 'laboratuvar'], ['emoji', 'karistir']],
      a: 'Oda sohbetinde + menüsünden “İki emojiyi birleştir” bölümünü açıp iki emoji seç. Desteklenen çiftler için hazır birleştirilmiş görsel aranır; desteklenmeyen çiftlerde uygulama bunları görsel çıkartmaya dönüştürür. Sonucu göndermeden önce önizlemede kontrol edebilirsin.' },
    { groups: [['aurai', 'hata'], ['aurai', 'calism'], ['aurai', 'yanit'], ['yapay', 'zeka', 'hata']],
      a: 'AURAI önce selamlaşmalar ve Aura X yardım bilgisi için yerel cevapları kullanır; diğer sorular için `aurai-chat` Edge Function ve model sağlayıcısının yapılandırılması gerekir. Genel sorulara yanıt alamıyorsan Edge Function’ın yayımlanmış olduğunu ve sunucu secret’larının doğru olduğunu kontrol et. Gizli API anahtarını HTML dosyasına ekleme.' },
    { groups: [['tema', 'artir'], ['daha', 'fazla', 'tema'], ['baloncuk', 'rengi'], ['konusma', 'baloncuk']],
      a: 'Oda içindeyken palet simgesini aç. Arka plan temasını seçebilir, koyu veya açık baloncuk renklerinden birini kullanabilir ya da şeffaf modu açabilirsin. Bu görsel tercihler yalnızca senin cihazında saklanır.' },
    { groups: [['profil', 'gonderi'], ['gonderilerimi', 'gor'], ['begeni', 'sayisi'], ['mesajlarimi', 'oku']],
      a: 'Profilim ekranının altındaki “Hesap Etkinliğim” bölümünde kendi gönderilerini, beğendiğin gönderileri ve özel mesajlarını görebilirsin. Özet kutuları gönderi sayını, gönderilerine gelen beğenileri ve gelen özel mesajlarını gösterir.' },
    { groups: [['durum', 'paylas'], ['durum', 'olustur'], ['hikaye', 'paylas'], ['hikaye', 'olustur'], ['durum', 'koy']],
      a: 'Durum/hikâye paylaşmak için Keşfet’in üstündeki durum şeridinde “Oluştur” kutusuna dokun. Metnini yaz, istersen görsel veya video ekle, sonra “Paylaş”a bas. Durumlar 24 saat görünür; yeni durum paylaşınca öncekinin yerine geçer. Gizlilik kuralına göre bir kişinin hikâyesini yalnızca o kişiyi takip edenler görebilir.\n\nPaylaşım hata verirse oturum açık mı, medya yükleme izinleri ve statuses tablosu RLS kuralları doğru mu kontrol edilir; ekrandaki tam hata mesajı teşhisi hızlandırır.' },
    { groups: [['mod', 'sec'], ['mod', 'degis'], ['mod', 'ayarla'], ['modu', 'nasil'], ['mod']],
      a: 'Modunu profilinde “Modun” alanından seçebilirsin: profil düzenleme ekranını aç, modunu seç ve kaydet. Mod seçip Keşfet’e gönderi atarsan adının altında küçük bir etiket olarak görünür.' },
    { groups: [['tema'], ['baloncuk'], ['arka', 'plan'], ['seffaf'], ['palet']],
      a: 'Oda içinde başlıktaki palet simgesine dokun. Arka plan için mevcut uzay temalarından birini seçebilirsin. Şeffaf modu açarsan baloncuklar kapanır ve mesajlar arka planın üstüne yazılır. Bu ayarlar sana özel olarak bu cihazda saklanır.' },
    { groups: [['tepki'], ['emoji', 'tepki'], ['emoji', 'ver'], ['reaksiyon']],
      a: 'Bir mesajın yanındaki gülen yüz simgesine dokun ve bir emoji seç. Her kişi bir mesaja tek tepki verebilir; yeni tepki seçersen öncekinin yerine geçer. Tepkiler odadaki herkese görünür.' },
    { groups: [['oda', 'olustur'], ['oda', 'ac'], ['yeni', 'oda'], ['oda', 'kur']],
      a: 'Odalar bölümünden yeni oda oluşturabilirsin. Oda adını yazıp oluşturduktan sonra odaya girip mesajlaşmaya başlayabilirsin. Özel oda oluşturursan katılmak isteyenlerin parolayı girmesi gerekir.' },
    { groups: [['oda', 'katil'], ['odaya', 'gir'], ['oda', 'bul']],
      a: 'Odalar bölümünde mevcut odaları görüp katılabilirsin. Özel bir odaya katılmak için oda sahibinin verdiği parolayı girmen gerekir.' },
    { groups: [['sifre'], ['giris', 'yapam'], ['giris', 'sorun'], ['giris', 'olmuyor'], ['unuttum']],
      a: 'Giriş ekranında “Şifremi Unuttum” seçeneğini kullanarak sıfırlamayı başlatabilirsin. Giriş yapamıyorsan önce kullanıcı adı ve şifreni kontrol et. Hata devam ederse tam hata mesajını paylaş; parolanı veya doğrulama kodunu gönderme.' },
    { groups: [['profil', 'duzenle'], ['profil', 'degis'], ['kullanici', 'adi', 'degis'], ['hakkinda', 'yazi']],
      a: 'Profil ekranından görünen adını, hakkında yazını ve modunu düzenleyebilirsin. Kullanıcı adı değiştirirken aynı adın başka bir hesapta kullanılmaması gerekir.' },
    { groups: [['takip'], ['takipci'], ['kullanici', 'bul'], ['arama']],
      a: '“Kullanıcı Bul” bölümünden kişileri arayıp takip edebilirsin. Takip ettiğin kişilerin gönderilerini ve durumlarını görebilirsin.' },
    { groups: [['gonderi', 'paylas'], ['gonderi', 'at'], ['post', 'at'], ['gonderi', 'duzenle'], ['gonderi', 'sil']],
      a: 'Keşfet’teki paylaşım alanından metin, görsel veya video ile gönderi paylaşabilirsin. Kendi gönderini düzenleyebilir veya silebilirsin; başkalarının gönderilerine beğeni ve yorum yapabilirsin.' },
    { groups: [['cizim'], ['cizim', 'tahta']],
      a: 'Odada “Çizim” düğmesiyle ortak çizim tahtası açılır. Bu özellik oda ayarına bağlıdır; kilitliyse oda yöneticisinden izin istemen gerekir.' },
    { groups: [['youtube'], ['video', 'senkron']],
      a: 'Odalarda senkron YouTube oynatma oda ayarına ve yetkiye bağlıdır. Kilitliyse oda yöneticisinden izin istemen gerekir.' },
    { groups: [['iphone', 'centik'], ['centik'], ['iphone', 'kesik'], ['ust', 'kisim', 'kesik']],
      a: 'Üst kısım çentik alanına göre ayarlandı. Hâlâ kesik görünüyorsa sayfayı yenile ve Safari veya Chrome’u güncelle. Sorun sürerse ekran görüntüsüyle birlikte hangi cihazı ve tarayıcıyı kullandığını yazabilirsin.' },
    { groups: [['aura', 'nedir'], ['aura', 'x', 'ne'], ['bu', 'uygulama', 'ne']],
      a: 'Aura X bir sosyal ağ uygulamasıdır. Profil, Keşfet akışı, gönderiler, 24 saatlik durumlar, takip, odalar ve mesajlaşma özellikleri bulunur.' },
    { groups: [['oy', 'ver'], ['oy', 'nasil'], ['liderlik']],
      a: 'Bir kullanıcının gönderisindeki “Oy Ver” düğmesiyle oy verebilirsin. Oy sayıları liderlik tablosunu etkiler.' },
  ];
  function kbAnswer(text) {
    const words = norm(text).split(' ').filter(Boolean);
    if (!words.length) return '';
    for (const entry of KB) {
      if (entry.groups.some(g => groupMatches(words, g))) return entry.a;
    }
    return '';
  }
  const FALLBACK_HELP = 'Bunu şu anda kesin olarak yanıtlayamadım. 💜 Aura X ile ilgiliyse hangi ekranı kullandığını ve gördüğün tam hata mesajını yaz; adım adım ilerleyelim. Genel bir konuysa sunucu model bağlantısı yapılandırılmamış olabilir. İstersen desteklenen cihazlarda yerel AURAI modelini de isteğe bağlı olarak bu cihazda çalıştırabilirsin.';

  // Üretim desteği ve regresyon testleri için salt-okunur metotlar.
  window.__auraiLogic = { fold, skel, smalltalk, identity, kbAnswer };

  const CRISIS_RE = /\b(intihar|kendimi oldur\w*|kendime zarar|canima kiy\w*|yasamak istemiyorum|olmek istiyorum|hayatima son|kendimi as\w*|kendimi atac\w*|kendimi kes\w*|artik yasayamam|suicid\w*|kill myself|hurt myself|harm myself|want to die|i don t want to live|do not want to live)\b/;
  const EMERGENCY_RE = /\b(nefes alamiyorum|nefes alamiyor|kalp krizi|bilinci kapali|bayildi|agir kaza|trafik kazasi|yangin cikti|evde yangin|saldiriya ugr\w*|ciddi yarali|ambulans lazim|acil yardim lazim|canim tehlikede|can t breathe|cannot breathe|not breathing|heart attack|unconscious|need an ambulance|medical emergency)\b/;
  const el = (tag, cls, text) => {
    const n = document.createElement(tag);
    if (cls) n.className = cls;
    if (text !== undefined) n.textContent = text;
    return n;
  };
  const safeUrl = (value) => {
    try {
      const u = new URL(String(value || ''), window.location.href);
      return (u.protocol === 'https:' || u.protocol === 'http:') ? u.href : '';
    } catch (_) { return ''; }
  };

  // ---------- Görsel arayüz ----------
  const style = el('style');
  style.textContent = `
  #auraiFab{position:fixed;right:14px;bottom:calc(88px + env(safe-area-inset-bottom,0px));z-index:9998;display:none;align-items:center;gap:8px;padding:12px 16px;border:1px solid #ffffff2b;border-radius:999px;color:#fff;font-weight:800;font-size:14px;cursor:pointer;background:linear-gradient(135deg,var(--primary,#8b5cf6),var(--accent,#ec4899));box-shadow:0 8px 26px #0009;transition:transform .18s ease,box-shadow .18s ease}
  #auraiFab:hover{transform:translateY(-2px);box-shadow:0 12px 32px #000a}
  #auraiPanel{position:fixed;z-index:9999;right:0;bottom:0;width:100%;height:min(82dvh,780px);min-height:430px;display:none;flex-direction:column;background:var(--bg-surface,#121216);color:var(--text-main,#f4f4f8);border:1px solid #ffffff1a;border-radius:22px 22px 0 0;box-shadow:0 -12px 42px #000a;padding-bottom:env(safe-area-inset-bottom,0px);overflow:hidden}
  #auraiPanel.open{display:flex;animation:auraiRise .18s ease-out}
  @keyframes auraiRise{from{opacity:.65;transform:translateY(10px)}to{opacity:1;transform:translateY(0)}}
  @media(min-width:700px){#auraiPanel{right:18px;bottom:18px;width:420px;height:min(680px,calc(100dvh - 36px));min-height:480px;border-radius:20px}}
  #auraiHead{display:flex;align-items:center;gap:10px;padding:13px 14px;border-bottom:1px solid #ffffff14;background:linear-gradient(135deg,#8b5cf617,#ec489908);flex-shrink:0}
  .auraiMark{display:grid;place-items:center;width:38px;height:38px;border-radius:13px;background:linear-gradient(135deg,#8b5cf6,#ec4899);font-size:20px;box-shadow:0 5px 18px #8b5cf633}
  .auraiHeadText{min-width:0;flex:1;display:flex;flex-direction:column;gap:2px}
  #auraiHead b{font-size:14px;letter-spacing:.6px}
  #auraiStatus{font-size:11px;color:var(--text-muted,#9ca3af)}
  .auraiIconBtn{border:1px solid #ffffff22;background:#ffffff06;color:var(--text-main,#ddd);border-radius:10px;width:34px;height:34px;display:grid;place-items:center;font-size:17px;cursor:pointer}
  .auraiIconBtn:hover{background:#ffffff12}
  #auraiLog{flex:1;min-height:0;overflow:auto;overscroll-behavior:contain;padding:14px;display:flex;flex-direction:column;gap:11px;scroll-behavior:smooth}
  .auraiMsg{position:relative;max-width:94%;padding:11px 12px;border-radius:15px;font-size:13.5px;line-height:1.6;overflow-wrap:anywhere;background:var(--bg-surface-hover,#1a1a20);border:1px solid #ffffff12;box-shadow:0 2px 8px #00000010}
  .auraiMsg.me{align-self:flex-end;max-width:90%;background:linear-gradient(135deg,var(--primary,#8b5cf6),#7547d9);border-color:transparent;color:#fff;border-bottom-right-radius:5px}
  .auraiMsg.assistant{align-self:flex-start;border-bottom-left-radius:5px}
  .auraiMsg.err{color:#ffb5bd;border-color:#ef444455}
  .auraiMsg.pending{color:var(--text-muted,#9ca3af);display:flex;align-items:center;gap:8px}
  .auraiDots{display:inline-flex;gap:3px}.auraiDots i{width:5px;height:5px;border-radius:50%;background:currentColor;animation:auraiDot 1s infinite ease-in-out}.auraiDots i:nth-child(2){animation-delay:.12s}.auraiDots i:nth-child(3){animation-delay:.24s}
  @keyframes auraiDot{0%,60%,100%{opacity:.28;transform:translateY(0)}30%{opacity:1;transform:translateY(-3px)}}
  .auraiRichLine{display:block;min-height:1em}.auraiRichLine+.auraiRichLine{margin-top:3px}.auraiRichList{padding-left:14px;position:relative}.auraiRichList:before{content:'•';position:absolute;left:1px;color:#c4b5fd}
  .auraiMsg strong{font-weight:800}.auraiMsg code{font-family:ui-monospace,SFMono-Regular,Consolas,monospace;font-size:.92em;background:#0003;padding:2px 5px;border-radius:5px}.auraiMsg pre{white-space:pre;overflow:auto;max-width:100%;padding:10px;border-radius:9px;background:#0005;margin:7px 0;font-size:12px}
  .auraiMsg a{color:#c4b5fd;text-decoration:underline;text-underline-offset:2px}.auraiMsg.me a{color:#fff}
  .auraiMsgActions{display:flex;justify-content:flex-end;margin-top:7px}
  .auraiCopyBtn{border:0;background:transparent;color:var(--text-muted,#9ca3af);font-size:11px;cursor:pointer;padding:3px 5px;border-radius:6px}.auraiCopyBtn:hover{background:#ffffff12;color:inherit}
  .auraiWelcome{display:flex;flex-wrap:wrap;gap:7px;margin-top:2px}
  .auraiPrompt{padding:8px 10px;border:1px solid #8b5cf644;border-radius:999px;background:#8b5cf610;color:var(--text-main,#f4f4f8);font-size:11.5px;cursor:pointer;text-align:left}
  .auraiPrompt:hover{background:#8b5cf626;border-color:#8b5cf688}
  .auraiSearchCard{align-self:stretch;max-width:100%;}
  .auraiSearchItem{padding:9px 0;border-top:1px solid #ffffff13}.auraiSearchItem:first-of-type{border-top:0}.auraiSearchTitle{font-weight:800;font-size:13px}.auraiSearchSnippet{font-size:12px;opacity:.85;margin:4px 0}.auraiSearchLink{font-size:11px;display:inline-block;word-break:break-all}
  .auraiCall{display:block;margin-top:10px;padding:13px;border-radius:12px;background:linear-gradient(135deg,#21c55d,#15803d);color:#fff!important;text-align:center;font-weight:900;text-decoration:none!important;box-shadow:0 4px 14px #16a34a44}
  .auraiBtn{display:block;margin-top:9px;padding:11px;width:100%;border:1px solid #8b5cf655;border-radius:12px;background:linear-gradient(135deg,#8b5cf61c,#ec489918);color:var(--text-main,#fff);font-weight:800;cursor:pointer;text-align:left}
  #auraiForm{display:flex;align-items:flex-end;gap:8px;padding:10px 12px;border-top:1px solid #ffffff14;background:var(--bg-surface,#121216);flex-shrink:0}
  #auraiIn{flex:1;min-width:0;resize:none;max-height:120px;padding:11px 12px;border-radius:13px;border:1px solid #ffffff20;background:var(--bg-base,#050507);color:var(--text-main,#fff);font-size:16px;line-height:1.45;font-family:inherit;outline:none}
  #auraiIn:focus{border-color:#8b5cf6aa;box-shadow:0 0 0 3px #8b5cf61a}
  #auraiSend{border:0;border-radius:13px;min-width:45px;height:44px;padding:0 13px;color:#fff;font-size:19px;font-weight:800;cursor:pointer;background:linear-gradient(135deg,var(--primary,#8b5cf6),var(--accent,#ec4899))}
  #auraiSend:disabled{opacity:.42;cursor:not-allowed}
  #auraiFootnote{font-size:10px;color:var(--text-muted,#9ca3af);text-align:center;padding:0 10px 8px;background:var(--bg-surface,#121216)}
  @media(prefers-reduced-motion:reduce){#auraiPanel.open{animation:none}.auraiDots i{animation:none}}
  `;
  document.head.appendChild(style);

  const fab = el('button', '', '✨ AURAI');
  fab.id = 'auraiFab'; fab.type = 'button'; fab.setAttribute('aria-label', 'AURAI sohbetini aç'); fab.setAttribute('aria-haspopup', 'dialog');
  const panel = el('section');
  panel.id = 'auraiPanel'; panel.setAttribute('role', 'dialog'); panel.setAttribute('aria-modal', 'false'); panel.setAttribute('aria-label', 'AURAI destek ve sohbet');
  const head = el('div'); head.id = 'auraiHead';
  const mark = el('div', 'auraiMark', '✦'); mark.setAttribute('aria-hidden', 'true');
  const headText = el('div', 'auraiHeadText');
  const title = el('b', '', 'AURAI');
  const status = el('span', '', 'Destek ve sohbet'); status.id = 'auraiStatus';
  headText.append(title, status);
  const clearBtn = el('button', 'auraiIconBtn', '↻'); clearBtn.type = 'button'; clearBtn.title = 'Yeni sohbet'; clearBtn.setAttribute('aria-label', 'Yeni sohbet başlat');
  const closeBtn = el('button', 'auraiIconBtn', '×'); closeBtn.type = 'button'; closeBtn.title = 'Kapat'; closeBtn.setAttribute('aria-label', 'AURAI panelini kapat');
  head.append(mark, headText, clearBtn, closeBtn);
  const log = el('div'); log.id = 'auraiLog'; log.setAttribute('role', 'log'); log.setAttribute('aria-live', 'polite'); log.setAttribute('aria-relevant', 'additions text');
  const form = el('form'); form.id = 'auraiForm';
  const input = el('textarea'); input.id = 'auraiIn'; input.rows = 1; input.maxLength = 2000; input.setAttribute('aria-label', 'AURAI mesajı'); input.placeholder = 'Bir şey sor… (araştırma için /ara konu)';
  const send = el('button', '', '↑'); send.id = 'auraiSend'; send.type = 'submit'; send.setAttribute('aria-label', 'Mesajı gönder');
  form.append(input, send);
  const footnote = el('div', '', 'AURAI hata yapabilir. Özel bilgilerini veya parolanı paylaşma.'); footnote.id = 'auraiFootnote';
  panel.append(head, log, form, footnote);
  document.body.append(fab, panel);

  let msgs = [];
  let busy = false;
  let signedIn = false;
  let authUserId = null;
  let sessionEpoch = 0;
  let localEngine = null;
  let localLoading = false;
  let localOfferShown = false;
  const sb = () => window.supabaseClient;

  // Mini Markdown gösterimi. İçerik sadece DOM metin düğümleriyle eklenir; HTML çalıştırılmaz.
  function appendInline(parent, value) {
    const text = String(value || '');
    const tokenRe = /\*\*[^*]+\*\*|`[^`]+`|\[[^\]]+\]\(https?:\/\/[^)\s]+\)|https?:\/\/[^\s]+/g;
    let at = 0, match;
    while ((match = tokenRe.exec(text))) {
      if (match.index > at) parent.append(document.createTextNode(text.slice(at, match.index)));
      const token = match[0];
      if (token.startsWith('**') && token.endsWith('**')) {
        parent.append(el('strong', '', token.slice(2, -2)));
      } else if (token.startsWith('`') && token.endsWith('`')) {
        parent.append(el('code', '', token.slice(1, -1)));
      } else {
        let label = token, href = token;
        if (token[0] === '[') {
          const m = token.match(/^\[([^\]]+)\]\((https?:\/\/[^)\s]+)\)$/);
          if (m) { label = m[1]; href = m[2]; }
        } else {
          const trailing = /[.,!?;:)\]]+$/.exec(href);
          if (trailing) href = href.slice(0, -trailing[0].length);
          label = href;
        }
        const url = safeUrl(href);
        if (!url) parent.append(document.createTextNode(token));
        else {
          const a = el('a', '', label); a.href = url; a.target = '_blank'; a.rel = 'noopener noreferrer';
          parent.append(a);
          if (token.startsWith('http') && token.length > href.length) parent.append(document.createTextNode(token.slice(href.length)));
        }
      }
      at = tokenRe.lastIndex;
    }
    if (at < text.length) parent.append(document.createTextNode(text.slice(at)));
  }
  function renderRichText(container, value) {
    const lines = String(value || '').replace(/\r\n?/g, '\n').split('\n');
    let inCode = false, codeLines = [], lastLine = null;
    const flushCode = () => {
      const pre = el('pre');
      pre.append(el('code', '', codeLines.join('\n')));
      container.append(pre); codeLines = [];
    };
    lines.forEach((line) => {
      if (/^\s*```/.test(line)) {
        if (inCode) flushCode();
        inCode = !inCode;
        lastLine = null;
        return;
      }
      if (inCode) { codeLines.push(line); return; }
      const heading = /^(#{1,3})\s+(.+)$/.exec(line);
      const item = /^\s*[-*•]\s+(.+)$/.exec(line);
      const node = el('div', 'auraiRichLine' + (item ? ' auraiRichList' : ''));
      if (heading) node.append(el('strong', '', heading[2]));
      else appendInline(node, item ? item[1] : line);
      if (!line && lastLine) node.style.minHeight = '.45em';
      container.append(node);
      lastLine = line;
    });
    if (inCode) flushCode();
  }
  function addMessage(text, role, options) {
    const opts = options || {};
    const classes = ['auraiMsg', role === 'user' ? 'me' : 'assistant'];
    if (opts.pending) classes.push('pending');
    if (opts.error) classes.push('err');
    const node = el('div', classes.join(' '));
    if (opts.pending) {
      node.setAttribute('role', 'status');
      node.append(el('span', '', text));
      const dots = el('span', 'auraiDots'); dots.setAttribute('aria-hidden', 'true'); dots.append(el('i'), el('i'), el('i')); node.append(dots);
    } else {
      renderRichText(node, text);
    }
    if (opts.copy && role !== 'user') {
      const actions = el('div', 'auraiMsgActions');
      const copy = el('button', 'auraiCopyBtn', 'Kopyala'); copy.type = 'button'; copy.setAttribute('aria-label', 'Yanıtı kopyala');
      copy.addEventListener('click', async () => {
        try {
          await navigator.clipboard.writeText(String(text || ''));
          copy.textContent = 'Kopyalandı ✓';
        } catch (_) {
          const range = document.createRange(); range.selectNodeContents(node);
          const selection = window.getSelection(); selection.removeAllRanges(); selection.addRange(range);
          copy.textContent = 'Metni seçtim';
        }
        setTimeout(() => { copy.textContent = 'Kopyala'; }, 1700);
      });
      actions.append(copy); node.append(actions);
    }
    log.append(node);
    log.scrollTop = log.scrollHeight;
    return node;
  }
  function add(text, cls) {
    const node = addMessage(text, cls === 'me' ? 'user' : 'assistant', { error: cls === 'err', pending: cls === 'pending' });
    if (cls === 'me') node.classList.add('me');
    return node;
  }
  function addWelcome() {
    addMessage('Merhaba! Ben AURAI 💜 Aura X kullanımı ve hata çözümünde yardımcı olurum; istersen genel konularda da sohbet edebiliriz. Nereden başlayalım?', 'assistant', { copy: true });
    const chips = el('div', 'auraiWelcome');
    [
      ['Aura X hakkında', 'Aura X hakkında bilgi verir misin?'],
      ['Bir sorunu çözelim', 'Aura X’te bir sorun yaşıyorum, birlikte çözelim.'],
      ['Genel sohbet', 'Seninle biraz sohbet etmek istiyorum.'],
      ['Güncel bilgi ara', '/ara Türkiye teknoloji gündemi'],
    ].forEach(([label, prompt]) => {
      const b = el('button', 'auraiPrompt', label); b.type = 'button';
      b.addEventListener('click', () => {
        input.value = prompt;
        input.focus();
        resizeInput();
        if (prompt.startsWith('/ara ')) input.setSelectionRange(input.value.length, input.value.length);
        else form.requestSubmit();
      });
      chips.append(b);
    });
    log.append(chips);
  }
  function clearChat() {
    if (busy) return;
    msgs = [];
    localOfferShown = false;
    log.replaceChildren();
    addWelcome();
    input.value = '';
    resizeInput();
    input.focus();
  }
  function crisisCard() {
    if (log.querySelector('[data-aurai-emergency="true"]')) return;
    const guidance = 'Seni ciddiye alıyorum. Şu an senin ya da başka birinin güvenliği yakın tehlikedeyse Türkiye’de 112 Acil Çağrı Merkezi’ni ara. Ben kendiliğimden arama başlatamam. Yanında güvendiğin biri varsa hemen ona da haber ver. Buradayım, yazmaya devam edebilirsin.';
    const m = addMessage(guidance, 'assistant', { copy: true });
    m.dataset.auraiEmergency = 'true';
    const a = el('a', 'auraiCall', '📞 112’yi ara'); a.href = 'tel:112'; a.setAttribute('aria-label', 'Telefon uygulamasında 112 aramasını başlat'); m.append(a);
    msgs.push({ role: 'assistant', content: guidance });
    msgs = msgs.slice(-16);
  }
  function reply(text) {
    addMessage(text, 'assistant', { copy: true });
    msgs.push({ role: 'assistant', content: text });
    msgs = msgs.slice(-16);
  }
  function resizeInput() {
    input.style.height = 'auto';
    input.style.height = Math.min(input.scrollHeight, 120) + 'px';
  }
  function setBusy(value) {
    busy = value;
    send.disabled = value;
    input.disabled = value;
    status.textContent = value ? 'Yanıt hazırlanıyor…' : 'Destek ve sohbet';
  }

  async function searchNotes(query, requestEpoch) {
    const client = sb();
    if (!client) { reply('Arama servisine bağlanamıyorum. Lütfen oturumunu yenileyip tekrar dene.'); return true; }
    const cleanQuery = String(query || '').trim().slice(0, 200);
    if (!cleanQuery) { reply('Neyi araştırmamı istersin? Örneğin: **/ara Türkiye uzay programı güncel haberler**'); return true; }
    const pending = addMessage('İnternette kaynak arıyorum…', 'assistant', { pending: true });
    try {
      const { data, error } = await client.functions.invoke('aurai-search', { body: { query: cleanQuery } });
      if (requestEpoch !== sessionEpoch) { pending.remove(); return true; }
      let d = data;
      if (error) { try { d = await error.context.json(); } catch (_) { d = null; } }
      pending.remove();
      if (!d || !Array.isArray(d.results) || !d.results.length) {
        const msg = (d && d.error) || 'Bu sorgu için sonuç bulunamadı. Biraz daha kısa veya farklı kelimelerle dene.';
        addMessage(msg, 'assistant', { copy: true, error: true });
        return true;
      }
      const box = el('div', 'auraiMsg assistant auraiSearchCard');
      renderRichText(box, '## Araştırma sonuçları\n' + cleanQuery);
      const sourceTexts = [];
      d.results.slice(0, 5).forEach((r, i) => {
        const item = el('div', 'auraiSearchItem');
        const titleText = String(r && r.title || 'Başlıksız sonuç').slice(0, 300);
        const snippetText = String(r && r.snippet || '').slice(0, 900);
        const linkUrl = safeUrl(r && r.link);
        item.append(el('div', 'auraiSearchTitle', (i + 1) + '. ' + titleText));
        if (snippetText) item.append(el('div', 'auraiSearchSnippet', snippetText));
        if (linkUrl) {
          const link = el('a', 'auraiSearchLink', linkUrl); link.href = linkUrl; link.target = '_blank'; link.rel = 'noopener noreferrer';
          item.append(link);
        }
        box.append(item);
        sourceTexts.push(titleText + ': ' + snippetText + (linkUrl ? ' (' + linkUrl + ')' : ''));
      });
      log.append(box);
      log.scrollTop = log.scrollHeight;
      msgs.push({ role: 'assistant', content: 'Araştırma kaynakları (' + cleanQuery + '):\n' + sourceTexts.join('\n') });
      msgs = msgs.slice(-16);
      return true;
    } catch (err) {
      pending.remove();
      if (requestEpoch !== sessionEpoch) return true;
      addMessage('Arama şu anda çalışmıyor. Biraz sonra tekrar dene; istersen sorunu normal sohbet şeklinde de sorabilirsin.', 'assistant', { copy: true, error: true });
      console.warn('AURAI arama hatası:', err && err.message);
      return true;
    }
  }
  function isSearchRequest(text) {
    const n = norm(text);
    return /^\/ara(?:\s|$)/i.test(String(text || '').trim()) ||
      /\b(?:internette|internetten|webde|google da)\s+(?:ara|arastir\w*|bak\w*|bul\w*)\b/.test(n) ||
      /\b(?:kaynak|kaynakca)\s+(?:bul|goster|ver|ara)\b/.test(n) ||
      /\b(?:arastir\w*|internetten bak|son haberler|guncel haberler|guncel bilgi ara|guncel fiyat|bugunku haberler|en son haber|en guncel)\b/.test(n);
  }
  function searchQuery(text) {
    return String(text || '').trim()
      .replace(/^\/ara\s*/i, '')
      .replace(/^(?:internette ara|internetten ara|webde ara|kaynak bul|kaynakli bilgi|arastir|internetten bak)\s*/i, '')
      .trim();
  }
  function offerLocalModel() {
    if (localEngine || localLoading || localOfferShown) return;
    localOfferShown = true;
    if (!navigator.gpu) {
      log.append(el('div', 'auraiBtn', 'Yerel model bu tarayıcıda desteklenmiyor. Genel sohbet için sunucu bağlantısının yapılandırılması gerekir.'));
      log.scrollTop = log.scrollHeight;
      return;
    }
    const b = el('button', 'auraiBtn', '🧠 Yerel AURAI modelini bu cihazda yükle (ilk seferde ' + LOCAL_MODEL_SIZE + ' veri; isteğe bağlı)');
    b.type = 'button';
    b.addEventListener('click', () => { b.remove(); localOfferShown = false; loadLocalModel(); });
    log.append(b); log.scrollTop = log.scrollHeight;
  }
  async function loadLocalModel() {
    if (!navigator.gpu) {
      addMessage('Bu tarayıcıda WebGPU desteği görünmüyor. Güncel masaüstü Chrome veya desteklenen bir cihazla deneyebilirsin.', 'assistant', { copy: true, error: true });
      localOfferShown = false; offerLocalModel(); return;
    }
    localLoading = true;
    const statusMessage = addMessage('Yerel model indiriliyor… İlk kurulumda ' + LOCAL_MODEL_SIZE + ' veri gerekebilir.', 'assistant', { pending: true });
    try {
      const webllm = await import('https://esm.run/@mlc-ai/web-llm@0.2.86');
      localEngine = await webllm.CreateMLCEngine(LOCAL_MODEL_ID, {
        initProgressCallback: (p) => { statusMessage.replaceChildren(document.createTextNode('Yerel model hazırlanıyor… %' + Math.round((p.progress || 0) * 100))); },
      });
      statusMessage.classList.remove('pending'); statusMessage.replaceChildren(); renderRichText(statusMessage, 'Yerel AURAI hazır 💜 Bundan sonraki yerel yanıtlar bu cihazda üretilir.');
    } catch (err) {
      statusMessage.classList.remove('pending'); statusMessage.classList.add('err'); statusMessage.replaceChildren(document.createTextNode('Yerel model yüklenemedi. Tarayıcı belleğini ve WebGPU desteğini kontrol edip yeniden deneyebilirsin.'));
      console.warn('AURAI yerel model yüklenemedi:', err && err.message);
      localOfferShown = false; offerLocalModel();
    } finally { localLoading = false; log.scrollTop = log.scrollHeight; }
  }
  async function localAnswer() {
    const history = [{ role: 'system', content: LOCAL_SYSTEM }, ...msgs.slice(-12)];
    const result = await localEngine.chat.completions.create({ messages: history, temperature: 0.65, max_tokens: 700 });
    return String(result.choices && result.choices[0] && result.choices[0].message && result.choices[0].message.content || '').trim();
  }

  fab.addEventListener('click', () => {
    panel.classList.add('open'); fab.style.display = 'none';
    panel.setAttribute('aria-modal', 'false'); input.focus();
  });
  closeBtn.addEventListener('click', () => {
    panel.classList.remove('open'); panel.setAttribute('aria-modal', 'false'); refreshFab(); fab.focus();
  });
  clearBtn.addEventListener('click', clearChat);
  input.addEventListener('input', resizeInput);
  input.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' && !e.shiftKey && !e.isComposing) { e.preventDefault(); form.requestSubmit(); }
    if (e.key === 'Escape' && panel.classList.contains('open')) closeBtn.click();
  });
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && panel.classList.contains('open') && document.activeElement !== input) closeBtn.click();
  });

  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    const q = input.value.trim();
    if (!q || busy) return;
    const requestEpoch = sessionEpoch;
    setBusy(true);
    input.value = ''; resizeInput();
    addMessage(q, 'user');
    msgs.push({ role: 'user', content: q });
    msgs = msgs.slice(-16);
    try {
      const n = norm(q);
      if (CRISIS_RE.test(n) || EMERGENCY_RE.test(n)) { crisisCard(); return; }

      const quick = identity(q) || smalltalk(q);
      if (quick) { reply(quick); return; }

      // Açıkça istenen internet araştırmasını ürün bilgi tabanından önce ayır.
      if (isSearchRequest(q)) { await searchNotes(searchQuery(q), requestEpoch); return; }

      // Ürünle ilgili bilinen yanıtları model çağrısından önce ver: daha hızlı, tutarlı ve maliyetsiz.
      const kb = kbAnswer(q);
      if (kb) { reply(kb); return; }

      // Genel sohbet için sunucu modeli kullanılır.
      const client = sb();
      if (client) {
        const pending = addMessage('Biraz düşünüyorum…', 'assistant', { pending: true });
        try {
          const { data, error } = await client.functions.invoke('aurai-chat', { body: { messages: msgs.slice(-16), mode: 'assistant' } });
          if (requestEpoch !== sessionEpoch) { pending.remove(); return; }
          let d = data;
          if (error) { try { d = await error.context.json(); } catch (_) { d = null; } }
          if (d && d.crisis) crisisCard();
          if (d && d.answer) {
            pending.remove();
            addMessage(String(d.answer), 'assistant', { copy: true });
            msgs.push({ role: 'assistant', content: String(d.answer) });
            msgs = msgs.slice(-16);
            return;
          }
          throw new Error((d && d.error) || 'Yanıt alınamadı.');
        } catch (err) {
          pending.remove();
          if (requestEpoch !== sessionEpoch) return;
          console.warn('AURAI sunucu modeli yanıt vermedi:', err && err.message);
        }
      }

      if (localEngine) {
        try {
          const answer = await localAnswer();
          if (requestEpoch !== sessionEpoch) return;
          if (answer) { reply(answer); return; }
        } catch (err) { console.warn('AURAI yerel model hatası:', err && err.message); }
      }
      reply(FALLBACK_HELP);
      offerLocalModel();
    } catch (err) {
      if (requestEpoch === sessionEpoch) {
        console.error('AURAI hatası:', err);
        addMessage('Beklenmedik bir hata oluştu. Mesajını yeniden göndermeyi deneyebilirsin.', 'assistant', { copy: true, error: true });
      }
    } finally {
      if (requestEpoch === sessionEpoch) {
        setBusy(false);
        log.scrollTop = log.scrollHeight;
        if (panel.classList.contains('open')) input.focus();
      }
    }
  });

  function refreshFab() {
    fab.style.display = signedIn && !panel.classList.contains('open') ? 'inline-flex' : 'none';
    if (!signedIn) { panel.classList.remove('open'); panel.setAttribute('aria-modal', 'false'); }
  }
  function watch() {
    const client = sb();
    if (!client || !client.auth) { setTimeout(watch, 400); return; }
    client.auth.getSession().then(({ data }) => {
      const session = data && data.session;
      authUserId = session && session.user ? session.user.id : null;
      signedIn = !!session;
      refreshFab();
    }).catch(() => { signedIn = false; authUserId = null; refreshFab(); });
    client.auth.onAuthStateChange((_event, session) => {
      const nextUserId = session && session.user ? session.user.id : null;
      if (authUserId && authUserId !== nextUserId) {
        // Oturum kapanır/değişirse eski isteklerin sonraki hesapta cevap göstermesini engelle.
        sessionEpoch += 1;
        msgs = [];
        localOfferShown = false;
        log.replaceChildren();
        input.value = '';
        resizeInput();
        setBusy(false);
      }
      authUserId = nextUserId;
      signedIn = !!session;
      if (!signedIn) { msgs = []; localOfferShown = false; log.replaceChildren(); input.value = ''; resizeInput(); }
      else if (!log.childNodes.length) addWelcome();
      refreshFab();
    });
  }
  addWelcome();
  watch();
})();
