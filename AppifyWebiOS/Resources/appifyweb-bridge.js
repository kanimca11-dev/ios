(function () {
  'use strict';
  if (window.top !== window || window.AppifyWeb || !window.AppifyNative) return;
  function send(type, payload) {
    window.AppifyNative.postMessage(JSON.stringify({version: 1, type: type, payload: payload || {}}));
  }
  var api = {
    version: 1,
    ready: function () { send('ready'); },
    navigate: function (path) { send('navigate', {path: path}); },
    requestNotifications: function () { send('requestNotifications'); },
    share: function (text, url) { send('share', {text: text, url: url}); },
    updateUserIdentity: function (id, email, name) { send('identity', {id: id, email: email, name: name}); },
    clearUserIdentity: function () { send('logout'); },
    setUserTags: function (tags) { send('tags', {tags: typeof tags === 'string' ? JSON.parse(tags) : tags}); },
    requestFCMToken: function () { send('fcmToken'); },
    getAppVersion: function () { return window.__appifyVersion || '1.0'; },
    hasUserIdentity: function () { return window.__appifyHasIdentity ? 'true' : 'false'; }
  };
  window.AppifyWeb = api;
  // Compatibility methods route through the same main-frame, origin-checked channel.
  window.SaaS = api;
  window.AndroidSessionSync = {syncUserSession: function (json) { send('session', {json: json}); }};
  function routeChanged() { send('routeChanged', {url: location.href}); }
  ['pushState', 'replaceState'].forEach(function (name) {
    var original = history[name];
    history[name] = function () { var result = original.apply(this, arguments); routeChanged(); return result; };
  });
  window.addEventListener('popstate', routeChanged);
  window.addEventListener('hashchange', routeChanged);
  window.addEventListener('appify:navigate', function (event) {
    // A site may prevent the default by handling appify:navigate itself.
    if (!event.defaultPrevented && event.detail && event.detail.path) location.assign(event.detail.path);
  });
  api.routeChanged = routeChanged;
  api.onNavigate = function (handler) {
    window.addEventListener('appify:beforeNavigate', function (event) {
      if (handler(event.detail.path) !== false) event.preventDefault();
    });
  };
  window.addEventListener('appify:scrollToTop', function () {
    var scrollRoot = document.querySelector('[data-app-scroll-root]') || document.scrollingElement;
    if (scrollRoot) scrollRoot.scrollTo({top: 0, behavior: 'smooth'});
  });
  document.addEventListener('touchstart', function (event) {
    var node = event.target, atTop = true;
    while (node && node !== document) {
      if (node.scrollHeight > node.clientHeight && /auto|scroll/.test(getComputedStyle(node).overflowY)) {
        if (node.scrollTop > 0) atTop = false;
      }
      node = node.parentNode;
    }
    send('scrollState', {atTop: atTop});
  }, {passive: true});
  var scrollPending = false;
  document.addEventListener('scroll', function () {
    if (scrollPending) return;
    scrollPending = true;
    requestAnimationFrame(function () {
      scrollPending = false;
      var root = document.querySelector('[data-app-scroll-root]') || document.scrollingElement;
      if (root) send('scrollPosition', {x: Math.round(root.scrollLeft), y: Math.round(root.scrollTop)});
    });
  }, {passive: true, capture: true});
  function boot() {
    if (window.__appifyAppMode || document.documentElement.hasAttribute('data-app-mode')) {
      document.documentElement.classList.add('appify-native');
      var style = document.createElement('style');
      style.textContent = '.appify-native [data-app-hide]{display:none!important}';
      document.head.appendChild(style);
    }
    routeChanged();
    // Explicit data-app-managed-ready delegates readiness to the site's own data/render lifecycle.
    if (!document.documentElement.hasAttribute('data-app-managed-ready')) {
      var appRoot = document.querySelector('#app, #root');
      function afterPaint() { requestAnimationFrame(function () { requestAnimationFrame(api.ready); }); }
      // DOMContentLoaded can precede asynchronous Vue/React route mounting.
      // Wait for real root content rather than revealing an empty SPA document.
      if (appRoot && !appRoot.childElementCount && window.MutationObserver) {
        var mounted = new window.MutationObserver(function () {
          if (appRoot.childElementCount) { mounted.disconnect(); afterPaint(); }
        });
        mounted.observe(appRoot, {childList: true});
      } else afterPaint();
    }
    window.dispatchEvent(new CustomEvent('appify:available', {detail: {version: 1}}));
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot, {once: true});
  else boot();
})();
