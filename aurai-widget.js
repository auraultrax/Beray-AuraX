/* AURAI - AuraX içi sohbet paneli. Yalnızca giriş yapmış kullanıcıya görünür.
   Backend: supabase/functions/aurai-chat. Mevcut koda dokunmaz; index.html'e tek satırla eklenir. */
(function () {
  'use strict';
  if (window.__auraiWidget) return;
  window.__auraiWidget = true;

  const norm = (s) => s.toLocaleLowerCase('tr-TR').normalize('NFD').replace(/[\u0300-\u036f]/g, '').replace(/ı/g, 'i').replace(/[^a-z0-9\s]/g, ' ').replace(/\s+/g, ' ').trim();
  const CRISIS_RE = /\b(intihar|kendimi oldur\w*|kendime zarar|canima kiy\w*|yasamak istemiyorum|olmek istiyorum|hayatima son|kendimi as\w*|kendimi atac\w*|kendimi kes\w*|artik yasayamam)\b/;
  const EMERGENCY_RE = /\b(nefes alamiyorum|nefes alamiyor|kalp krizi|bilinci kapali|bayildi|agir kaza|trafik kazasi|yangin cikti|evde yangin|saldiriya ugr|ciddi yarali|ambulans lazim|acil yardim lazim|canim tehlikede)\b/;
  const SMALLTALK_WORDS = new Set(['merhaba','selam','slm','sa','as','selamun','aleykum','aleyküm','aslm','gunaydin','günaydin','iyi','aksamlar','akşamlar','geceler','nasilsin','nasılsın','naber','ne','haber','nabersin','napion','napiyon','napiyorsun','iyiyim','iyidir','sen','siz','misin','mi','lan','kanka','dostum','hey','hello','hi','orada','misin','aktif','misin']);
  const SMALLTALK_REPLIES = [
    'Merhaba! 😊 Buradayım. İstersen Aura X hakkında birlikte ilerleyelim, istersen biraz gündelik sohbet edelim. Sen nasılsın?',
    'İyiyim diyelim, işlemciler bugün kahvesini içmiş gibi 😄 Sen nasılsın? Aura X tarafında da bir şeye takıldıysan beraber çözeriz.',
    'Naber! 😄 Ben AURAI. Aura X kurulumu, özellikler ve hatalar konusunda yardımcı olurum; gündelik sohbet de edebiliriz. Sende ne var ne yok?'
  ];
  const quickReply = (text) => {
    const n = norm(text);
    if (/^(kimsin|sen kimsin|aurai kimsin|ne ise yariyorsun|ne ise yararsin)$/.test(n)) return 'Ben AURAI’yim 💜 Aura X’in kurulum, kullanım ve sorun giderme danışmanıyım. Özellikleri anlatabilir, hataları adım adım çözmene yardım edebilir ve gündelik sohbete de katılabilirim.';
    if (/^(aurai aktif mi|aurai yayinda mi|aurai online mi|aurai calisiyor mu)$/.test(n)) return 'AURAI paneli açık ve mesajını aldım. 😊 Daha kapsamlı yanıtlar için Supabase’te aurai-chat Edge Function’ının ve model bağlantısı secrets ayarlarının da doğru çalışması gerekiyor.';
    const words = n.split(' ').filter(Boolean);
    if (words.length && words.length <= 7 && words.some(w => ['merhaba','selam','slm','sa','naber','nasilsin','hello','hi','hey','gunaydin','iyi','aksamlar','geceler'].includes(w)) && words.every(w => SMALLTALK_WORDS.has(w) || ['naber','nasilsin','merhaba','selam','hello','hi','hey','gunaydin','geceler','aksamlar','iyi','slm','sa'].includes(w))) {
      const idx = /naber|napion|napiyon|ne haber/.test(n) ? 2 : /nasilsin|iyi misin/.test(n) ? 1 : 0;
      return SMALLTALK_REPLIES[idx];
    }
    return '';
  };
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
  #auraiHead button.on{background:var(--primary,#8b5cf6);border-color:transparent;color:#fff}
  #auraiLog{flex:1;overflow:auto;padding:14px;display:flex;flex-direction:column;gap:10px}
  .auraiMsg{max-width:88%;padding:10px 12px;border-radius:14px;font-size:14px;line-height:1.55;white-space:pre-wrap;overflow-wrap:anywhere;background:var(--bg-surface-hover,#1a1a20);border:1px solid #ffffff14}
  .auraiMsg.me{align-self:flex-end;background:var(--primary,#8b5cf6);border-color:transparent}
  .auraiMsg.err{color:#ffabb3}
  .auraiCall{display:block;margin-top:10px;padding:13px;border-radius:12px;background:linear-gradient(135deg,#21c55d,#15803d);color:#fff;text-align:center;font-weight:900;text-decoration:none;box-shadow:0 4px 14px #16a34a44}
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
  const sb = () => window.supabaseClient;

  function add(text, cls) { const m = el('div', 'auraiMsg' + (cls ? ' ' + cls : ''), text); log.append(m); log.scrollTop = log.scrollHeight; return m; }
  function crisisCard() {
    const m = add('Seni ciddiye alıyorum. Eğer şu an senin ya da başka birinin güvenliği yakın tehlikedeyse Türkiye’de 112 Acil Çağrı Merkezi’ni ara. Aşağıdaki yeşil düğmeye sen basmalısın; ben telefonunda kendiliğimden arama başlatamam. Yanında güvenilir biri varsa hemen ona da haber ver. Buradayım, yazmaya devam edebilirsin.');
    m.dataset.auraiEmergency = 'true';
    const a = el('a', 'auraiCall', '📞 112’yi ara'); a.href = 'tel:112'; a.setAttribute('aria-label', 'Telefon uygulamasında 112 aramasını başlat'); m.append(a);
  }
  add('Merhaba! Ben AURAI 💜 Aura X kurulum, kullanım ve hata çözümünde yardımcı olurum; istersen gündelik sohbet de edebiliriz. Bir şey takılırsa beraber adım adım bakalım. 😊');

  fab.onclick = () => { panel.classList.add('open'); fab.style.display = 'none'; input.focus(); };
  closeBtn.onclick = () => { panel.classList.remove('open'); refreshFab(); };
  input.addEventListener('input', () => { input.style.height = 'auto'; input.style.height = Math.min(input.scrollHeight, 110) + 'px'; });
  input.addEventListener('keydown', (e) => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); form.requestSubmit(); } });

  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    const q = input.value.trim();
    if (!q || busy) return;
    const client = sb();
    busy = true; send.disabled = true; input.value = ''; input.style.height = 'auto';
    add(q, 'me'); msgs.push({ role: 'user', content: q });
    const n = norm(q);
    const localCrisis = CRISIS_RE.test(n) || EMERGENCY_RE.test(n);
    if (localCrisis) crisisCard();
    const quick = !localCrisis ? quickReply(q) : '';
    if (quick) {
      add(quick);
      msgs.push({ role: 'assistant', content: quick });
      msgs = msgs.slice(-16);
      busy = false; send.disabled = false; log.scrollTop = log.scrollHeight; input.focus();
      return;
    }
    if (!client) {
      add('Supabase bağlantısı henüz hazır değil; bu yüzden AURAI modeline ulaşamıyorum. Sayfayı yenile. Devam ederse Supabase bağlantı dosyasının ve URL/anahtar ayarlarının yüklendiğini kontrol et.', 'err');
      msgs.pop(); busy = false; send.disabled = false; return;
    }
    const pending = add('Biraz düşünüyorum…');
    try {
      const { data, error } = await client.functions.invoke('aurai-chat', { body: { messages: msgs.slice(-16), mode: 'assistant' } });
      let d = data;
      if (error) { try { d = await error.context.json(); } catch (_) { d = null; } }
      if (d && d.crisis && !localCrisis) crisisCard();
      if (!d || !d.answer) throw new Error((d && d.error) || 'AURAI yanıt alamadı. Supabase → Edge Functions → aurai-chat loglarını ve model bağlantısı ayarlarını kontrol et.');
      pending.textContent = d.answer;
      if (!d.limited) msgs.push({ role: 'assistant', content: d.answer }); else msgs.pop();
      msgs = msgs.slice(-16);
    } catch (err) {
      const reason = err && err.message ? err.message : 'AURAI şu anda yanıt veremiyor.';
      pending.textContent = reason;
      pending.classList.add('err');
      // Hata metni görünür kalsın; sadece başarısız kullanıcı mesajını bağlamdan çıkar.
      msgs.pop();
    } finally { busy = false; send.disabled = false; log.scrollTop = log.scrollHeight; input.focus(); }
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
