const {test}=require('node:test');
const assert=require('node:assert/strict');
const vm=require('node:vm');
const fs=require('node:fs');
const path=require('node:path');
const source=fs.readFileSync(path.join(__dirname,'../AppifyWebiOS/Resources/location-bridge.js'),'utf8');
function setup(frame=false){
 const sent=[];const window={AppifyNative:{postMessage:value=>sent.push(JSON.parse(value))}};
 window.top=frame?{}:window;const navigator={};
 vm.runInNewContext(source,{window,navigator});return{window,navigator,sent};
}
test('location bridge is not exposed to subframes',()=>{assert.equal(setup(true).navigator.geolocation,undefined);});
test('location returns native errors, watches persist and clear explicitly',()=>{
 const {window,navigator,sent}=setup();let count=0,error;
 navigator.geolocation.getCurrentPosition(()=>count++,value=>error=value);
 window.__appifyLocationReply(sent[0].payload.id,{error:{code:1,message:'disabled'}});
 assert.equal(error.code,1);assert.equal(count,0);
 const watch=navigator.geolocation.watchPosition(()=>count++);
 window.__appifyLocationReply(watch,{coords:{latitude:1}});window.__appifyLocationReply(watch,{coords:{latitude:2}});
 assert.equal(count,2);navigator.geolocation.clearWatch(watch);
 window.__appifyLocationReply(watch,{coords:{latitude:3}});assert.equal(count,2);
 assert.equal(sent.at(-1).type,'clearLocation');
});
