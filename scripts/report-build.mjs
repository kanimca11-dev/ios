import fs from 'node:fs';
import {https} from './prepare-build.mjs';
const event=JSON.parse(fs.readFileSync(process.env.GITHUB_EVENT_PATH,'utf8'));
const input=event.client_payload || event.inputs || {};
if (!/^\d+$/.test(String(input.app_id)) || !/^\d+$/.test(String(input.build_id))) throw Error('Invalid callback build identifiers');
const api=https(input.api_url || 'https://www.appifyweb24.com/backend/index.php/','API URL');
const file=fs.readFileSync('app-unsigned.ipa');
const form=new FormData();
form.append('status','completed');
form.append('file_size',String(file.length));
form.append('build_file',new Blob([file],{type:'application/octet-stream'}),'app-unsigned.ipa');
// This is a compilation artifact; the artifact filename and signing notice explicitly identify it as unsigned.
const response=await fetch(api.href.replace(/\/$/,'')+`/v1/app/${input.app_id}/build/${input.build_id}/webhook`,{method:'POST',headers:{'X-App-Token':input.app_token || ''},body:form,redirect:'error',signal:AbortSignal.timeout(60000)});
if (!response.ok) throw Error(`Build callback failed (${response.status})`);
