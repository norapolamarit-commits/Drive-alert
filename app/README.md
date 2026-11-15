# doz — Flutter companion app

The app is a prototype companion for the Doz ESP32-S3 wearable. It provides BLE device discovery/connect, a live status view, sensor history, alerts, profile/settings, and a chatbot page with local fallback. It is not a medical device and is not ready for public health-data use.

## Current behavior

- The bottom navigation has Status, Data, Ask doz, Device, and Profile.
- BLE uses `flutter_blue_plus`; the current app expects the Doz BLE service/live characteristic and firmware packet format configured in `lib/services/ble_service.dart`.
- `DozBleFrameAssembler` accepts bounded Doz fragments only after header/index/byte checks; it rejects truncated or oversized framed packets and passes legacy unframed notifications through. BLE frames still have no cryptographic device authentication or replay protection.
- `CloudService` accepts HTTPS endpoints (or debug-only loopback HTTP), bounds bearer headers and JSON request bytes, and limits event POSTs to `/sensor` or `/alert`; consent remains enforced by the calling app state and cloud health sync is currently hard-disabled.
- The checked-in acquisition firmware currently sends one-second mean Red/IR ADC counts and mean MPU6050 axes over BLE. It does not send HR, SpO₂, battery percentage, or AI inference; the app labels this as raw telemetry and does not invent a Safe result. Health Data charts switch to the available raw fields while this firmware is connected.
- Sensor history CSV exports `red_adc_mean`, `ir_adc_mean`, and `device_timestamp_ms` when present. Empty cells mean the reading did not include those fields; the one-second optical means are not full PPG waveforms.
- Android BLE permissions and iOS Bluetooth usage descriptions are configured. Physical-device verification on Android and iOS is still required.
- Account mode uses Supabase email/password Auth when configured. Without Auth build defines, local demo mode is available in debug only; release builds fail closed and show an Auth configuration error. Profile/health fields and alert history use platform secure storage with account-scoped keys; non-sensitive settings remain in SharedPreferences. If secure storage is unavailable, the app stops loading health/profile data and does not fall back to plaintext.
- Remote chatbot and automatic AI advice require a signed-in Supabase session, an HTTPS endpoint, and consent bound to that endpoint. Both requests carry the Supabase access token and the API verifies it; without consent/auth, the app does not send sensor values and uses local advice/fallback. Only the question/current sensor/current risk context is sent; profile fields and alert history are not.
- Remote AI advice additionally requires a fresh physical BLE reading: an active BLE connection, a reading marked as device-originated, and a sensor timestamp no more than ten seconds old; future timestamps are rejected. Cached remote advice is cleared when consent is revoked or the endpoint changes, and an in-flight advice result is discarded if consent or freshness has expired before it returns. An in-flight chat response is hidden after consent or endpoint changes; revoking consent cannot retract a request already sent. These checks protect privacy and freshness; they do not verify physiological accuracy.
- The Cloud API verifies Supabase bearer tokens for chatbot and event routes. `/chat` and `/advice` share a process-local per-account rate limit and concurrency cap. Server-side health-data read/write routes now fail closed unless `HEALTH_DATA_SYNC_ENABLED=true`; the deployment manifest keeps it false pending shared production rate limiting, retention/deletion, deployment security, and end-to-end ownership review. Do not send real health data to an unreviewed deployment.
- The in-app Thai/English privacy notice is a draft and requires legal/project-provider review before public release.

## Run locally

```bash
cd /Users/norapol/Downloads/Doz/app
flutter pub get
flutter run
```

For account-mode development, configure a Supabase project and pass only the project URL and publishable key:

```bash
flutter run \
  --dart-define=DOZ_SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=DOZ_SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
```

Never put a Supabase `service_role` or `sb_secret_` key in a mobile app. The app accepts a modern `sb_publishable_` key or a legacy JWT only when its decoded payload has `role=anon`; the release build script applies the same check. The redirect URI to allowlist in Supabase is `doz://login-callback/`.
For the Render web app, also allowlist `https://doz-web.onrender.com/` in Supabase Auth redirect URLs. Web sign-up and password-recovery emails return to that web origin; Android and iOS keep the `doz://login-callback/` deep link.

## Install on Android / iOS

See [`docs/DISTRIBUTION.md`](docs/DISTRIBUTION.md) for Supabase setup, Android APK/Play internal testing, iOS signing/TestFlight, and acceptance checks. iOS distribution requires macOS/Xcode signing; it is not a direct APK-style file install.

## Known release blockers

1. The cloud API verifies bearer tokens for chat, advice, and sensor/alert routes and binds events to the verified account. In-process rate limiting is implemented for both AI routes. Health-data routes fail closed by default; do not enable them until shared production rate limits, retention/deletion, deployment security, and end-to-end ownership controls are reviewed.
2. An account-deletion flow is implemented in the app and `DELETE /account` API, but it cannot be considered live until the API is deployed with the server-only `SUPABASE_SERVICE_ROLE_KEY` and deletion is verified end-to-end in a non-production project. Secure local storage must still be verified on each target OS/device before distribution; Android app backup is disabled to avoid copying health data outside the secure-storage boundary.
3. Verify sign-up confirmation and password-recovery deep links on physical iOS/Android devices.
4. Verify BLE service/characteristic UUID, packet protocol, fragmented notifications, disconnect/reconnect, and permission denial against the exact production firmware.
5. Finalize the privacy notice with controller/processor names, data region/retention, contact, and legal review.

Related project scope and release gate: [`../docs/APPLICATION_SCOPE_AND_RELEASE_PLAN_DRAFT.md`](../docs/APPLICATION_SCOPE_AND_RELEASE_PLAN_DRAFT.md).
