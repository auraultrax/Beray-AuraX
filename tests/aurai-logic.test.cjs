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

test('kimlik sorusuna AURAI olarak yanıt verir', () => {
  assert.match(logic.identity('Sen kimsin?'), /AURAI/);
});
