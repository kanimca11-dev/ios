# iOS native shell

The iOS template implements the Android shell's local-first startup, trusted website bridge, bounded tab sessions, native interactions, permission gates and branded build configuration. It targets iOS 15+.

Startup uses one visual launch screen. The static launch storyboard and the first SwiftUI frame use the same bundled logo, color and 128-point layout. iOS controls the real launch screen, so the identical continuation remains until the first page is ready; there is no second full-art design, zoom, or timed animation. Errors and biometric/configuration gates dismiss the continuation immediately. A bounded startup deadline prevents it from hiding errors forever.

## Cottkart preview on a Mac

The public preview settings in `preview/cottkart.json` contain the exact supplied logo and wizard artwork URLs and `https://cottkart.com/?app_webview=1`. Push is disabled; no customer token is included. The website keeps its own storefront navigation.

```sh
cd ios
node scripts/prepare-build.mjs preview/cottkart.json
python3 -m venv .build-tools
.build-tools/bin/pip install Pillow
.build-tools/bin/python scripts/prepare_assets.py
brew install xcodegen
xcodegen generate
open AppifyWebiOS.xcodeproj
```

In Xcode, choose your Apple development team and a registered bundle identifier, then select an iPhone or simulator and run. The configuration script writes build settings and bundled JSON for the current build. Customer CI uses an isolated checkout and its own backend payload instead of the preview file.

## Implemented behavior

- Cached or build-injected config is available immediately; HTTPS API refresh runs in the background using `X-App-Token` and `/v1/config`. Saved disabled decisions remain disabled offline. Credential-bearing API redirects cannot leave the API origin.
- Up to three live `WKWebView` sessions preserve tab history and position. Up to five evicted interaction snapshots restore the tab URL and document scroll. Last selected tab and same-origin URL survive relaunch. Cookies and login storage remain in `WKWebsiteDataStore.default`; the legacy wholesale localStorage copy is removed.
- Native tab labels, selection feedback, edge-swipe Back, safe-area/keyboard layout, route-aware hidden paths and ordinary HTTP caching. Website headers/navigation are only hidden through the explicit shared app-mode contract, never broad CSS selectors.
- The Android website SDK is bundled unchanged. Document-start injection waits for SPA mounting/explicit readiness. WK messages require the main frame, exact HTTPS scheme/host/port, supported version and bounded payload. Hash routes and navigation commands use the same protocol as Android.
- Loading progress, completed-load pull refresh, offline banner, retryable errors, HTTP error handling, a load deadline and WebKit process-termination recovery. Existing content remains available when offline where WebKit's cache permits.
- External HTTPS links open in `SFSafariViewController`; supported phone/mail/SMS links use their native apps. Foreign origins never gain app bridge access. Universal links and push destinations are validated again before navigation; signed Associated Domains and the website's AASA file are required for universal-link delivery.
- Native share sheets, WebKit's HTML file/camera picker, context-based camera/microphone prompts, native media playback and downloaded-file sharing. Camera/microphone bridge prompts are limited to the interactive trusted main frame. Downloads use app-owned temporary files and preserve the originating WebKit session.
- Native Core Location access is enabled only by app configuration and the interactive trusted main frame. Requests trigger iOS consent when needed. Backgrounding, tab changes, locking and disabling location stop updates. The bridge supports one-shot location and watches; accuracy is approximately hundred-meter and browser `PositionOptions` are not currently mapped.
- Biometric/device-credential unlock and relock after 30 seconds in the background, without discarding live tab sessions.
- Optional Firebase Messaging integration maps APNs registration to FCM tokens for the existing backend. Tokens are not logged or sent as raw APNs strings. Registration uses `device_token`; identity/logout/tag updates use the versioned bridge and the backend's PUT identity endpoint. Updates are serialized; explicit identity metadata is kept in memory, not a copy of website storage. Push permission is contextual and feature-gated.

## Build and push setup

`build-ios.yml` now reads the backend's nested `config` fields, preserves the complete start URL/query, quotes injected values as data, generates the exact branding assets without cropping, and fails configured-image errors. The logo controls the app icon/launch logo; the wizard image supplies the matching launch background color. The default template assets remain generic.

The workflow builds a real unsigned IPA and clearly labels it `app-unsigned.ipa`; it fails if the `.app` is missing. An unsigned IPA cannot be installed on an iPhone. Apple signing/provisioning or TestFlight is still required. Signing credentials are not present in this workspace.

For push, add the matching `GoogleService-Info.plist` locally or repository secret `GOOGLE_SERVICE_INFO_PLIST_BASE64`. Configure an APNs key in Firebase and use an Apple provisioning profile with Push Notifications. Set `APS_ENVIRONMENT` to match the profile (development or production). The bundle ID in Firebase, Apple and the app must match. Firebase auto-init remains off until the remote/local feature is enabled. Without Firebase config or Apple signing, push delivery is not available.

## Verification

Run platform-independent tests with:

```sh
node --test scripts/bridge.test.cjs scripts/config.test.mjs scripts/location.test.cjs
```

The macOS `verify-ios.yml` workflow parses Swift sources, generates the project, compiles the app and runs five XCTest cases on an available iPhone simulator. Native policy/configuration tests cover spoofed origins, unsafe schemes, hash routes, sparse settings and disabled-state serialization.

On the current Windows workspace: 12 JavaScript/config/location tests passed; 14 Swift files passed a Tree-sitter syntax parse; project/workflow YAML and resource XML/JSON were validated. Swift syntax parsing does not establish SDK type correctness. Xcode compilation, XCTest execution, launch appearance, physical iPhone behavior, downloads, biometric/device permissions, login/payment returns and push delivery remain unverified. No IPA or iPhone install was claimed from this environment.

The optional Windows parser helper uses workspace-only tooling:

```sh
npm install --prefix .tools --no-save --ignore-scripts web-tree-sitter@0.20.8 tree-sitter-wasms yaml
node scripts/check-swift-syntax.cjs
```

Native catalog/cart/account/order screens still require the website's APIs and dedicated implementations, as on Android.
