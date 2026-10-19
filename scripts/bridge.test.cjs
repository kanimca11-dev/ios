const {test} = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const source = fs.readFileSync(require('node:path').join(__dirname, '../AppifyWebiOS/Resources/appifyweb-bridge.js'), 'utf8');

function environment({frame = false, managed = false, appMode = false, emptySpa = false} = {}) {
  const sent = [], handlers = {}, styles = [];
  const window = {
    AppifyNative: {postMessage: value => sent.push(JSON.parse(value))},
    addEventListener: (name, handler) => (handlers[name] ||= []).push(handler),
    dispatchEvent: event => { (handlers[event.type] || []).forEach(fn => fn(event)); return !event.defaultPrevented; }
  };
  window.top = frame ? {} : window;
  const appRoot = {childElementCount: 0};
  let mutation;
  window.MutationObserver = class {
    constructor(callback) { mutation = callback; }
    observe() {}
    disconnect() {}
  };
  const root = {scrollLeft: 0, scrollTop: 0, scrollTo() {}};
  const document = {
    readyState: 'complete',
    documentElement: {hasAttribute: name => name === 'data-app-managed-ready' ? managed : appMode, classList: {add() {}}},
    head: {appendChild: node => styles.push(node)},
    createElement: () => ({}), querySelector: selector => emptySpa && selector === '#app, #root' ? appRoot : null,
    scrollingElement: root,
    addEventListener: (name, fn) => (handlers['document:' + name] ||= []).push(fn)
  };
  const history = {pushState() {}, replaceState() {}};
  class CustomEvent {
    constructor(type, options = {}) { this.type = type; Object.assign(this, options); this.defaultPrevented = false; }
    preventDefault() { if (this.cancelable) this.defaultPrevented = true; }
  }
  const context = {window, document, history, location: {href: 'https://shop.example.com/', assign() {}}, CustomEvent,
    requestAnimationFrame: fn => fn(), getComputedStyle: () => ({overflowY: 'auto'})};
  vm.runInNewContext(source, context);
  return {window, sent, handlers, styles, context, mount: () => { appRoot.childElementCount = 1; mutation(); }};
}
test('bridge never exposes native capabilities in subframes', () => {
  const {window, sent} = environment({frame: true});
  assert.equal(window.AppifyWeb, undefined);
  assert.equal(sent.length, 0);
});
test('managed SPA signals readiness explicitly, ordinary pages signal once', () => {
  const ordinary = environment();
  assert.equal(ordinary.sent.filter(m => m.type === 'ready').length, 1);
  vm.runInNewContext(source, ordinary.context);
  assert.equal(ordinary.sent.filter(m => m.type === 'ready').length, 1);
  const managed = environment({managed: true});
  assert.equal(managed.sent.some(m => m.type === 'ready'), false);
  managed.window.AppifyWeb.ready();
  assert.equal(managed.sent.at(-1).type, 'ready');
});
test('app-mode styling is opt-in and restricted to marked elements', () => {
  assert.equal(environment().styles.length, 0);
  const {styles} = environment({appMode: true});
  assert.equal(styles.length, 1);
  assert.match(styles[0].textContent, /data-app-hide/);
  assert.doesNotMatch(styles[0].textContent, /direction|height|overflow|input/);
});
test('empty SPA root does not report readiness until it mounts', () => {
  const spa = environment({emptySpa: true});
  assert.equal(spa.sent.some(message => message.type === 'ready'), false);
  spa.mount();
  assert.equal(spa.sent.filter(message => message.type === 'ready').length, 1);
});
test('SPA navigation can handle native commands without document reload', () => {
  const {window, context} = environment();
  let destination;
  window.AppifyWeb.onNavigate(path => { destination = path; });
  const e = new context.CustomEvent('appify:beforeNavigate', {cancelable: true, detail: {path: '/orders'}});
  assert.equal(window.dispatchEvent(e), false);
  assert.equal(destination, '/orders');
});
test('compatibility identity and navigation use the versioned message channel', () => {
  const {window, sent} = environment();
  window.SaaS.updateUserIdentity('42', 'person@example.com', 'Person');
  assert.deepEqual(sent.at(-1), {version: 1, type: 'identity', payload: {id: '42', email: 'person@example.com', name: 'Person'}});
  window.AppifyWeb.navigate('/cart');
  assert.equal(sent.at(-1).payload.path, '/cart');
});
