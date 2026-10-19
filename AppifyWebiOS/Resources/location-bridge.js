(function () {
  'use strict';
  if (window.top !== window || !window.AppifyNative) return;
  var callbacks = {}, next = 1;
  function request(success, failure, watch) {
    var id = next++;
    callbacks[id] = {success: success, failure: failure, watch: watch};
    window.AppifyNative.postMessage(JSON.stringify({version: 1, type: 'location', payload: {id: id, watch: watch}}));
    return id;
  }
  window.__appifyLocationReply = function (id, result) {
    var callback = callbacks[id];
    if (!callback) return;
    if (!callback.watch || result.error) delete callbacks[id];
    if (result.error) { if (callback.failure) callback.failure(result.error); }
    else if (callback.success) callback.success(result);
  };
  Object.defineProperty(navigator, 'geolocation', {configurable: true, value: {
    getCurrentPosition: function (success, failure) { request(success, failure, false); },
    watchPosition: function (success, failure) { return request(success, failure, true); },
    clearWatch: function (id) {
      delete callbacks[id];
      window.AppifyNative.postMessage(JSON.stringify({version: 1, type: 'clearLocation', payload: {id: id}}));
    }
  }});
})();
