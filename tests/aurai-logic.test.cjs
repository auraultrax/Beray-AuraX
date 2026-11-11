const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

class FakeClassList {
  constructor(owner) { this.owner = owner; this.values = new Set(); }
  add(...values) { values.forEach(v => this.values.add(v)); }
  remove(...values) { values.forEach(v => this.values.delete(v)); }
  contains(value) { return this.values.has(value); }
}
class FakeNode {
  constructor(tag = 'div', text = '') {
    this.tagName = tag;
    this.textContent = text;
    this.children = [];
    this.style = {};
    this.dataset = {};
    this.attributes = {};
    this.listeners = {};
    this.className = '';
    this.classList = new FakeClassList(this);
    this.value = '';
    this.scrollHeight = 0;
  }
  append(...nodes) { this.children.push(...nodes); nodes.forEach(n => { if (n && typeof n === 'object') n.parentNode = this; }); }
  appendChild(node) { this.append(node); return node; }
  setAttribute(name, value) { this.attributes[name] = String(value); }
  addEventListener(name, callback) { (this.listeners[name] ||= []).push(callback); }
  replaceChildren(...nodes) { this.children = []; this.append(...nodes); }
  remove() { if (this.parentNode) this.parentNode.children = this.parentNode.children.filter(n => n !== this); }
  querySelector() { return null; }
  focus() {}
  setSelectionRange() {}
  requestSubmit() {}
}

function loadLogic() {
  const document = {
    head: new FakeNode('head'),
    body: new FakeNode('body'),
    createElement: tag => new FakeNode(tag),
    createTextNode: text => new FakeNode('#text', String(text)),
    addEventListener() {},
    activeElement: null,
  };
  const window = {
    location: { href: 'https://example.test/' },
    supabaseClient: { auth: { getSession: async () => ({ data: { session: null } }), onAuthStateChange() {} } },
  };
  const context = { window, document, console, URL, setTimeout, clearTimeout, navigator: {}, Promise, RegExp, String, Math };
  vm.runInNewContext(fs.readFileSync(path.join(__dirname, '..', 'aurai-widget.js'), 'utf8'), context, { timeout: 1500 });
  return window.__auraiLogic;
}

const logic = loadLogic();

test('Türkçe karakterleri tutarlı normalleştirir', () => {
  assert.equal(logic.fold('ŞİFREMİ UNUTTUM'), 'sifremi unuttum');
});

test('kısaltılmış selamlaşmayı tanır', () => {
  assert.match(logic.smalltalk('slm'), /Merhaba/);
});

test('Aura X durum paylaşımı sorusunu yanıtlar', () => {
  assert.match(logic.kbAnswer('Durum nasıl paylaşılır?'), /24 saat/);
});

test('oda katılımında Türkçe ekleri tolere eder', () => {
  assert.match(logic.kbAnswer('Odalara nasıl katılırım?'), /parola/);
});

test('kısa kökler ilgisiz kelimelerde yanlış pozitif üretmez', () => {
  assert.equal(logic.kbAnswer('Modem çalışmıyor'), '');
});

test('kimlik sorusuna BAI olarak yanıt verir', () => {
  assert.match(logic.identity('Sen kimsin?'), /BAI/);
});

test('doğal Türkçe selamlaşma çeşitlerini tanır', () => {
  assert.match(logic.smalltalk('Günaydın'), /Merhaba/);
  assert.match(logic.smalltalk('Çok sağ ol'), /Rica ederim/);
});

test('BAI gündelik diyaloglara doğal karşılık verir', () => {
  assert.match(logic.smalltalk('Ben de iyiyim'), /Buna sevindim/);
  assert.match(logic.smalltalk('Espri yapsana'), /Wi.?Fi|bağlantı/i);
  assert.match(logic.smalltalk('Offf çok sıkıcısın yaaa'), /Haklısın/);
});

test('hesap silme için gerekli sunucu kurulumunu açıklar', () => {
  assert.match(logic.kbAnswer('Hesabımı silemiyorum'), /delete-account/);
});

test('uygulama dışı bildirim için push kurulumunu açıklar', () => {
  assert.match(logic.kbAnswer('Uygulama kapalıyken bildirim gelmiyor'), /VAPID/);
});

test('özel mesaj ekranının sekmeli kullanımını açıklar', () => {
  assert.match(logic.kbAnswer('Özel mesaj nasıl gönderilir?'), /Özel Bildirimler/);
});
