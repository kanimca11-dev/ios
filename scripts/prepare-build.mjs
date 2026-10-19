import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

export function https(value, label) {
  const url = new URL(value);
  if (url.protocol !== 'https:' || url.username || url.password) throw Error(`${label} must be an HTTPS URL without credentials`);
  return url;
}
const bool = value => value === true || value === 1 || value === '1' || value === 'true';
const list = value => {
  if (typeof value === 'string') { try { value = JSON.parse(value); } catch { value = []; } }
  return Array.isArray(value) ? value : [];
};
export function normalize(event) {
  const input = event.client_payload || event.inputs || event;
  const c = input.config || {};
  const target = https(input.target_url || c.targetUrl || '', 'target_url');
  const start = new URL(c.startUrl || c.start_url || target.href, target);
  if (https(start.href, 'start URL').origin !== target.origin) throw Error('Start URL must use the website origin');
  const tabs = list(c.navigationTabs ?? c.navigation_json).filter(tab => {
    if (!tab || typeof tab.label !== 'string' || typeof tab.path !== 'string') return false;
    try { return https(new URL(tab.path, target).href, 'tab').origin === target.origin; } catch { return false; }
  }).slice(0, 5).map(tab => ({label: tab.label.slice(0, 60), icon: String(tab.icon || 'home').slice(0, 60), path: tab.path}));
  return {
    targetUrl: target.href, startUrl: start.href,
    primaryColor: c.primaryColor || c.primary_color || '#008000',
    secondaryColor: c.secondaryColor || c.secondary_color || input.secondary_color || '#FFFFFF',
    splashLogoUrl: c.splashLogoUrl || c.splash_logo_url || null,
    splashImageUrl: c.splashImageUrl || c.splash_url || input.splash_url || null,
    userAgentSuffix: c.userAgentSuffix || c.user_agent_suffix || 'AppifyWeb/1.0',
    appModeEnabled: bool(c.appModeEnabled ?? c.app_mode_enabled),
    isActive: c.isActive === undefined ? true : bool(c.isActive),
    isSubscriptionActive: c.isSubscriptionActive === undefined ? true : bool(c.isSubscriptionActive),
    subscriptionExpiredMessage: c.subscriptionExpiredMessage || c.subscription_expired_message || 'Subscription expired.',
    features: {
      enablePushNotifications: bool(c.enablePushNotifications ?? c.enable_push),
      enableBiometrics: bool(c.enableBiometrics ?? c.enable_biometrics),
      enableLocation: bool(c.enableLocation ?? c.enable_location),
      showBottomNav: bool(c.showBottomNav ?? c.show_bottom_nav),
      screenOrientation: ['portrait', 'landscape', 'auto'].includes(c.screenOrientation || c.screen_orientation) ? (c.screenOrientation || c.screen_orientation) : 'portrait',
      navigationTabs: tabs,
      hiddenNavPaths: list(c.hiddenNavPaths ?? c.hidden_nav_paths).filter(x => typeof x === 'string').slice(0, 50)
    }
  };
}
export async function prepare(event, directory) {
  const input = event.client_payload || event.inputs || event;
  if (!input.target_url && !input.config?.targetUrl) {
    const base = https(input.api_url || 'https://www.appifyweb24.com/backend/index.php/', 'API URL');
    const response = await fetch(base.href.replace(/\/$/, '') + '/v1/config', {headers: {'X-App-Token': input.app_token || ''}, redirect: 'error', signal: AbortSignal.timeout(10000)});
    if (!response.ok) throw Error('Could not fetch app configuration');
    const remote = await response.json();
    input.target_url = remote.targetUrl;
    input.config = {...remote, ...remote.features, ...input.config};
    input.logo_url ||= remote.logoUrl;
  }
  const config = normalize(input);
  const token = input.app_token || 'default_token';
  if (!/^[A-Za-z0-9._-]+$/.test(token)) throw Error('Invalid platform app token');
  const bundleID = input.package_name || 'com.example.appifyweb';
  if (!/^[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+$/.test(bundleID)) throw Error('Invalid iOS bundle identifier');
  const name = String(input.app_name || 'AppifyWeb').slice(0, 128);
  if (/[\x00-\x1f]/.test(name)) throw Error('Invalid app name');
  const api = https(input.api_url || 'https://www.appifyweb24.com/backend/index.php/', 'API URL').href;
  let project = fs.readFileSync(path.join(directory, 'project.yml'), 'utf8');
  for (const [key, value] of Object.entries({APP_TOKEN: token, API_BASE_URL: api, CFBundleDisplayName: name, PRODUCT_BUNDLE_IDENTIFIER: bundleID})) {
    const pattern = new RegExp(`^(\\s*${key}:).*$`, 'm');
    if (!pattern.test(project)) throw Error(`Missing build field: ${key}`);
    project = project.replace(pattern, (_, prefix) => `${prefix} ${JSON.stringify(value)}`);
  }
  fs.writeFileSync(path.join(directory, 'project.yml'), project);
  fs.writeFileSync(path.join(directory, 'AppifyWebiOS/Resources/bundled-config.json'), JSON.stringify(config, null, 2));
  const assets = {logo_url: input.config?.logo_url || input.logo_url || input.logoUrl || '',
    splash_url: config.splashImageUrl, background: config.secondaryColor};
  fs.writeFileSync(path.join(directory, '.build-config.json'), JSON.stringify(assets, null, 2));
  // Associated domains are effective only after signing and website AASA configuration.
  fs.writeFileSync(path.join(directory, 'AppifyWebiOS/AppifyWeb.entitlements'), `<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>aps-environment</key><string>$(APS_ENVIRONMENT)</string><key>com.apple.developer.associated-domains</key><array><string>applinks:${new URL(config.targetUrl).hostname}</string></array></dict></plist>`);
  return config;
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const event = JSON.parse(fs.readFileSync(process.env.GITHUB_EVENT_PATH || process.argv[2], 'utf8'));
  await prepare(event, path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..'));
  console.log('Configured local startup settings and build resources.');
}
