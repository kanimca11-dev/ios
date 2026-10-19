import {test} from 'node:test';
import assert from 'node:assert/strict';
import {normalize} from './prepare-build.mjs';

test('backend nested payload preserves app mode query and parses false feature strings', () => {
  const value = normalize({client_payload: {target_url:'https://cottkart.com/?app_webview=1', config:{enable_push:'0',enable_biometrics:'false',navigation_json:'[{"label":"Home","icon":"home","path":"/"}]'}}});
  assert.equal(value.startUrl,'https://cottkart.com/?app_webview=1');
  assert.equal(value.features.enablePushNotifications,false);
  assert.equal(value.features.enableBiometrics,false);
  assert.equal(value.features.navigationTabs.length,1);
});
test('untrusted origin tabs and credential/HTTP URLs are rejected', () => {
  const value=normalize({target_url:'https://cottkart.com',config:{navigation_json:[{label:'bad',path:'https://cottkart.com.evil.test/'},{label:'ok',path:'/#/shop'}]}});
  assert.equal(value.features.navigationTabs.length,1);
  assert.throws(()=>normalize({target_url:'http://cottkart.com'}));
  assert.throws(()=>normalize({target_url:'https://u:p@cottkart.com'}));
  assert.throws(()=>normalize({target_url:'https://cottkart.com',config:{startUrl:'https://evil.test/'}}));
});
test('wizard artwork takes precedence and navigation lists remain bounded', () => {
  const value=normalize({target_url:'https://cottkart.com',splash_url:'https://assets.test/legacy.jpg',config:{splashImageUrl:'https://assets.test/wizard.jpg',splash_logo_url:'https://assets.test/logo.png',navigation_json:Array.from({length:10},(_,i)=>({label:'Tab',path:'/p'+i}))}});
  assert.equal(value.splashImageUrl,'https://assets.test/wizard.jpg');
  assert.equal(value.features.navigationTabs.length,5);
});
import os from 'node:os';
import fs from 'node:fs';
import path from 'node:path';
import {prepare} from './prepare-build.mjs';
test('build injection writes JSON settings and quoted YAML without interpreting names', async () => {
  const directory=fs.mkdtempSync(path.join(os.tmpdir(),'appify-ios-'));
  try {
    fs.mkdirSync(path.join(directory,'AppifyWebiOS/Resources'),{recursive:true});
    fs.copyFileSync(new URL('../project.yml',import.meta.url),path.join(directory,'project.yml'));
    const name='Cottkart "Preview" $(literal)';
    await prepare({app_name:name,package_name:'com.appifyweb.preview',target_url:'https://cottkart.com/?app_webview=1',config:{enable_push:'0'}},directory);
    const yaml=fs.readFileSync(path.join(directory,'project.yml'),'utf8');
    assert.ok(yaml.includes('CFBundleDisplayName: '+JSON.stringify(name)));
    const config=JSON.parse(fs.readFileSync(path.join(directory,'AppifyWebiOS/Resources/bundled-config.json'),'utf8'));
    assert.equal(config.startUrl,'https://cottkart.com/?app_webview=1');
    assert.equal(config.features.enablePushNotifications,false);
    assert.ok(fs.readFileSync(path.join(directory,'AppifyWebiOS/AppifyWeb.entitlements'),'utf8').includes('applinks:cottkart.com'));
  } finally {
    if(path.dirname(path.resolve(directory))!==path.resolve(os.tmpdir()) || !path.basename(directory).startsWith('appify-ios-')) throw Error('Refusing unexpected temporary cleanup path');
    fs.rmSync(directory,{recursive:true,force:true});
  }
});
