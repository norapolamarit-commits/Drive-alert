# doz Cloud API

## Local run

```sh
cd /Users/norapol/Documents/Doz/app/cloud_api
python3.11 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
uvicorn main:app --reload --host 127.0.0.1 --port 8000
```

For local backend regression tests, install the development test dependency and run the suite from this directory:

```sh
python -m pip install -r requirements-dev.txt
python -m pytest -q
```

The legacy `/dashboard` and `/local-dashboard` pages display in-process sensor/alert data and are disabled by default. To use them during local development only, start the server with `ENABLE_LOCAL_DEBUG_DASHBOARD=true`; keep the server bound to `127.0.0.1` as above and do not set this option on a public deployment. Their data is process-local and may not include events handled by other workers.

The Render blueprint pins Python to 3.11.16 (`PYTHON_VERSION`) to avoid inheriting different platform defaults. Use the same Python version for local development and API tests. Do not rely on Python 3.9, which is end-of-life and produced compatibility warnings in the previous local test run.

Configure `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` for authenticated routes. The mobile app must receive only the public/publishable key, never an admin key. The server rejects missing, non-ASCII/control-containing, or over-8,192-character bearer tokens before forwarding them to Supabase Auth. Configure `LLM_API_KEY` on the server to enable generated replies; without it, `/chat` returns an explicitly labeled knowledge/fallback response rather than claiming that an LLM answered.

The `/chat` route accepts a question up to 2,000 characters and a composed prompt up to 10,000 characters. The server selects its model from `LLM_MODEL`; a model name supplied by the mobile client is ignored. Authenticated `/chat` and `/advice` requests share a per-account process-local limit (defaults: 20 total AI requests per 60 seconds), and AI work across both routes is capped at two concurrent requests. The limiter tracks at most 10,000 identities per worker, rejects verified identity strings longer than 256 characters, prunes expired entries before refusing new ones, and returns HTTP 503 with `Retry-After` if the active identity table remains full. Override the request/concurrency defaults with `AI_RATE_LIMIT_MAX`, `AI_RATE_LIMIT_WINDOW_SECONDS`, and `AI_MAX_CONCURRENT_REQUESTS`. These in-memory safeguards reset on restart and are not shared across replicas; configure a shared gateway/provider rate limit and abuse monitoring before public or multi-instance production deployment.

Health-data routes (`GET/POST /sensor`, `GET/POST /alert`, `GET /overview`, and `GET /devices`) fail closed with HTTP 503 unless `HEALTH_DATA_SYNC_ENABLED=true` is set on the server. The server supports Supabase PostgreSQL, Firestore, or the optional Google Sheets adapter; configure only one. Process-memory storage is accepted only with the explicit `HEALTH_DATA_MEMORY_STORAGE_ENABLED=true` opt-in for local/evaluation use. That mode is ephemeral and responses identify it as `memory-ephemeral`. The deployment manifest leaves sync disabled; do not enable it until retention, account isolation, deletion, access controls, and shared rate limiting have been reviewed and tested. Chat/advice remain separate and can be enabled without turning on health-data storage.

### Supabase PostgreSQL storage (server only)

The API now supports the existing Supabase project's PostgreSQL database through its REST endpoint. Run `sql/001_supabase_health_events.sql` once in that project's SQL Editor. It creates a private-to-clients event table with RLS enabled and no browser/mobile policies. The server verifies each caller's Supabase Auth token, writes the verified owner ID, and uses `SUPABASE_SERVICE_ROLE_KEY` only on the API host. Never put that key in Flutter, the web build, or Git.

On the API service set `HEALTH_DATA_STORE=supabase`, `SUPABASE_URL`, and `SUPABASE_SERVICE_ROLE_KEY`. Leave `USE_FIRESTORE` unset and remove the Google Sheets storage settings so only one backend is selected. Keep `HEALTH_DATA_SYNC_ENABLED=false` until the table, retention, account deletion, and cross-account tests have been verified with test accounts. Then set it to `true` and confirm `/ready` returns 200 before accepting test telemetry. `POST /sensor` and `/alert` return `storage: supabase` only after the database confirms the write; reads and account deletion use the same table. Repeated identical events use a deterministic ID, excluding server receipt time, so retries do not duplicate rows.

This change is backend-only: the Flutter app's cloud health-data switch remains disabled and raw-only BLE readings still return before the upload path. Enabling this backend alone does not transmit device data. The database stores the API's validated event JSON, which currently may include legacy sensor fields; reduce the client payload to real telemetry before enabling production sync. `GET /devices` examines only the latest 500 sensor events, so a device absent from that window may not appear. The table has an owner/time index but no automatic retention or backups configured by this migration. Set retention, backup, and volume budgets before sustained collection.

### Google Sheets storage prototype

1. Use the empty dedicated prototype spreadsheet created for this task: `https://docs.google.com/spreadsheets/d/1Bo8vV7uvmzTfupZQZd4vfUsmk7cnbOOdBa1mTyznPCM/edit` (ID: `1Bo8vV7uvmzTfupZQZd4vfUsmk7cnbOOdBa1mTyznPCM`). It already contains the exact `SensorEvents` and `AlertEvents` headers; the project budget sheet is untouched. Enable the Google Sheets API in a Google Cloud project and create a service account. Share only the prototype spreadsheet with the service account email as Editor; Google documents direct file sharing with service accounts. Keep the spreadsheet ID and complete service-account JSON only in the backend's protected environment. Never put the JSON in Flutter, the repository, a Google Sheet cell, or a browser request.
2. Set `DOZ_SHEETS_SPREADSHEET_ID` and `DOZ_GOOGLE_SERVICE_ACCOUNT_JSON` on the API service. Leave `USE_FIRESTORE` unset. Locally, with those variables available to the process, run `python setup_sheets.py` from `app/cloud_api/`. It creates `SensorEvents` and `AlertEvents` with exactly `auth_user_id, received_at, event_id, event_json` as row 1 and refuses to overwrite unexpected headers.
3. Test with a non-production Supabase account. Only after an end-to-end privacy and deletion review set `HEALTH_DATA_SYNC_ENABLED=true`. The Flutter app currently keeps health-data cloud sync disabled, so configuring the server alone does not upload device data.

The Sheets adapter writes with `valueInputOption=RAW`, checks the verified account on reads, caps each tab at 2,000 data rows, and refuses oversized provider responses. **Clearing cells is not guaranteed erasure from Google Sheets version history**, so `DELETE /account` fails closed with HTTP 503 while this backend is selected; it does not claim to delete the user's account and health records. Do not treat this adapter as production storage for sensitive raw health data. Google Sheets API also has per-minute read/write quotas, and one event per second can exhaust a service account's quota. Use it for a limited prototype with non-sensitive or consented test data only; a database remains necessary for high-frequency raw telemetry and reliable deletion/retention. The adapter is not a migration tool for existing Firestore data.

`/advice` accepts only bounded `status` (1–80 characters), `alertLevel` (up to 40), and `sensor` text (up to 2,000 characters). Extra client fields are ignored, and the server always selects `LLM_MODEL`; callers cannot override the provider model.

Both `/chat` and `/advice` pass generated text through the same line-based deny-pattern filter for a limited set of diagnosis and medication-dose phrases. This is a defense-in-depth heuristic, not a complete medical-safety classifier or a guarantee that all unsafe wording is removed. Review the filter against the intended languages and use case before relying on generated health advice; fallback answers are separately fixed templates.

Provider responses for `/chat` and `/advice` are read incrementally with identity encoding and a 128 KiB raw-byte cap before JSON parsing; oversized, compressed, malformed, or non-text replies use the local fallback. The provider connection closes when the bounded read exits. Python JSON parsing still allocates objects proportional to the capped body, so the cap limits rather than eliminates parser memory use.

Before sending `LLM_API_KEY`, both `/chat` and `/advice` validate `LLM_BASE_URL` as a bounded HTTPS URL with a host and without embedded username/password, query, or fragment. Invalid endpoint configuration selects the local fallback and does not send the provider key. This prevents accidental plaintext or malformed destinations; the configured HTTPS host remains an operator-trusted destination and must be reviewed.

`GET /health` is a liveness check only: it can return `200` while protected routes are unusable. `GET /ready` checks that a valid HTTPS Supabase origin and public project key are configured; it returns `503` when those settings are absent, without disclosing their values. When health sync is enabled, readiness also requires an available storage backend and checks both Google Sheets tabs if Sheets is selected. It is still not a network check against Supabase or the LLM provider. Before connecting the app, check both endpoints, then test `/chat` and `/advice` using a non-production Supabase account and verify their response modes (`llm`/`fallback` and `rag`/`fallback`, respectively) and that invalid/expired tokens are rejected on both routes. Configure the app with that exact HTTPS host through `VITAGAURD_CLOUD_BASE_URL`; a local API or an unverified host must not be presented as a live AI service.

Use `preflight_chat.py` for a repeatable deployment check. It checks `/ready` before authenticated chat and advice, then confirms that both AI routes reject a fake token. `/health` remains a separate process-liveness check and cannot prove that Auth is configured. Supply a short-lived access token from a non-production test account through the environment; never put it in a source file or command history. The test requests contain no sensor or profile data, but if the server is configured for LLM mode they will be sent to the configured external model provider. The default accepts explicitly identified fallback modes; pass `--require-llm` to require actual LLM responses from both routes.

```sh
export DOZ_API_BASE_URL="https://<deployed-host>"
read -s "DOZ_CHAT_TEST_TOKEN?Short-lived test-account access token: "
printf '\n'
export DOZ_CHAT_TEST_TOKEN
python3.11 preflight_chat.py --require-llm
unset DOZ_CHAT_TEST_TOKEN
```

The hidden `read -s` prompt is for the macOS default `zsh`; do not type the token as part of a shell command. If preflight exits early, run `unset DOZ_CHAT_TEST_TOKEN` manually before continuing.

Run the backend regression tests from the app root after creating the virtual environment above:

```sh
cd /Users/norapol/Downloads/Doz/app
cloud_api/.venv/bin/python -m unittest discover -s cloud_api -p 'test_*.py' -v
```

The suite uses mocked Auth/provider requests and does not need production credentials or send user data. Keep the Python version aligned with the `PYTHON_VERSION` in `render.yaml`.

Deployment check (12 November 2026, Asia/Bangkok): Render service `Drive-alert` is connected to `norapolamarit-commits/Drive-alert`, branch `render-api-deploy`. Commit `8612060bba20f2efd0bf306ef53377a4d7623c10` deployed successfully as `dep-dbqan08473hc73cndd10`; dashboard reports `Deploy succeeded | Live`. Live `GET /health` returned `{"status":"ok"}` and `GET /` returned the service status JSON, both HTTP 200. The previous deployment's logs showed `POST /chat` → 503 before this commit; a successful authenticated `/chat` request has not been verified after deployment. The user's generic `{"detail":"Bad Request"}` still cannot be matched to a specific request/log: current source can emit HTTP 400 for duplicate/malformed (including overlong numeric) `Content-Length`, or when a supplied length does not match the received body on bounded POST routes. Missing `Content-Length` is allowed because the middleware enforces its limit while reading actual bytes. Capture response status, method/path, request ID, and timestamp; do not send access tokens or health payloads for diagnosis.

Request correlation: current source returns an opaque `X-Request-ID` on HTTP responses and logs only that ID, method, path, and status. For a matching live request, use the response header plus timestamp to find the Render log line; the server does not log body, Authorization header, sensor values, or query string. This source change is not live until deployed, and Render/proxy errors generated before the ASGI app may not include this header.

Troubleshooting `{"detail":"Bad Request"}`: the JSON text alone does not identify a cause. In the current API source, bounded POST routes can return HTTP 400 for duplicate/malformed `Content-Length`, a declared length that differs from the received body, or malformed/ambiguous JSON (including duplicate object keys and `NaN`/`Infinity`). Middleware-generated errors include a specific `detail`; the exact generic text `{"detail":"Bad Request"}` is not emitted by these middleware branches, so if that is the exact response body it may come from another route, an older deployment, or a proxy/platform layer. Normal `/chat` schema errors are HTTP 422; missing/invalid Bearer credentials are HTTP 401; an unconfigured Auth service is HTTP 503. A browser `GET /` returned HTTP 200 during the 12 November 2026 live check. To distinguish API from proxy errors, record HTTP status, method, path, timestamp, and `X-Request-ID` if present, then match it in Render Logs. Do not share Authorization headers, tokens, request bodies, or health data. If there is no `X-Request-ID`, the rejection may have happened before the request reached the checked-in middleware or the live service may be on a different revision.

Live probe on 12 November 2026: `GET /` and `GET /health` returned HTTP 200; `GET /chat` returned 405 as expected. A schema-valid, unauthenticated `POST /chat` returned HTTP 503 with `Chat authentication is not configured on this server.` This proves the deployed chat path currently cannot verify accounts until its Supabase URL and publishable key are configured in Render; no authenticated chat inference was attempted. These responses did not include `X-Request-ID`, although the checked-in middleware adds it, so the live deployment may be on a different source revision or an intermediary may be removing that header. This probe does not identify the user's original HTTP 400 request.

Local backend regression tests currently pass 48 tests using mocked Auth/provider calls; these do not prove live chat or a full production deployment. API request bodies are capped before parsing: 32 KiB for `/sensor` and `/alert`, 64 KiB for `/chat` and `/advice`. AI rate/concurrency and RAG numeric environment settings are finite, range-checked at import, and fail startup with a setting-specific error when invalid. The preflight script accepts `--require-llm` to distinguish generated replies from explicit fallback mode.

Strict JSON boundary: bounded POST routes reject duplicate object keys at any nesting level, malformed JSON, invalid encoded JSON, and non-standard `NaN`/`Infinity` numeric tokens with HTTP 400 before route validation or persistence. Empty bodies retain FastAPI's normal missing-body validation. These 400s are distinct from Pydantic field validation (422), authentication (401), and provider/storage configuration failures (503).

Firestore sensor/alert reads now query the authenticated user's per-device subcollections, filter the verified user ID, and merge the latest events. Reads fail closed if more than 16 device subcollections exist. This is a bounded guard, but a normal `/sensor` or `/alert` request can still read up to `16 × limit` documents (at the maximum query limit, 8,000 reads); consider pagination or a per-user event index before scaling usage. Device registration and event writes share a Firestore transaction on the user document, including one-time seeding from existing subcollections, so the per-account 16-device cap is enforced across workers. Existing accounts incur a one-time subcollection listing while their registry is first created.

`GET /devices` returns only each authenticated user's `deviceId` and `lastSeen`, not the complete latest sensor/alert event. Health data remains available only from the explicitly enabled, authenticated event routes.

Event minimization in the current source: Flutter sends only `deviceId` from its profile map; the API derives the owner from the verified bearer token. After validation, `/sensor` and `/alert` apply field allowlists before Firestore or in-memory persistence. Stored profile data is reduced to verified `userId` and validated `deviceId`; sensor and risk objects retain only fields used by the app. This is a source change and is not live until a new deployment is confirmed. Existing Firestore documents are not rewritten by this change.

Provider/model check (10 November 2026): Hugging Face's official public model API returned an empty `inferenceProviderMapping` for the configured model `nectec/Pathumma-llm-text-1.0.0`; merely setting `LLM_API_KEY` therefore does not establish that generated replies will work, and the API may return its explicit fallback. A separate official metadata query returned `KBTG-Labs/THaLLE-0.2-ThaiLLM-8B-fa` mapped to Featherless with `status=live` and task `conversational` at check time. This is only an alternative to review, not an approved model change or proof of a successful inference call. Verify provider/model availability and privacy/cost terms before changing; then require `preflight_chat.py --require-llm` to pass against the deployed service. These mappings can change. Hugging Face documents `inferenceProviderMapping` as the source for checking live providers: <https://huggingface.co/docs/inference-providers/hub-api#get-model-providers>.

### Render Blueprint setup

This is a monorepo: the Git repository root is `Doz/`, while the API and blueprint are under `app/cloud_api/`. When creating the Blueprint in Render, set **Blueprint Path** to `app/cloud_api/render.yaml`. The service definition sets `rootDir: app/cloud_api`, so the pip install and Uvicorn commands run in the directory containing `requirements.txt` and `main.py`. The Blueprint uses Render's current `runtime: python` field and checks `/health` after deploy. Do not create a second service from a different Blueprint path for the same API.

The three `sync: false` variables in the Blueprint must be entered in Render's protected environment settings: `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, and `SUPABASE_SERVICE_ROLE_KEY`; add `LLM_API_KEY` to enable generated chat replies. Keep the admin key server-side only. The `free` plan may sleep when idle and is only suitable for evaluation; verify latency and plan limits before relying on it for time-sensitive alerts.

Before sending a bearer token or admin key to Supabase, the API accepts `SUPABASE_URL` only as a bare HTTPS origin (host with optional port, no user information, path, query, or fragment). An invalid URL fails closed as a server configuration error; do not work around it by putting credentials in the URL.

## Account deletion

`DELETE /account` verifies the caller's Supabase bearer token, obtains the user ID from Supabase (the client cannot choose it), removes that user's API/Firestore sensor and alert records, then calls the Supabase Admin Users API to delete the account. The route fails closed with HTTP 503 when `SUPABASE_SERVICE_ROLE_KEY` is absent. Configure this secret only in the server's protected environment (for example Render's service environment); do not put it in `.env` committed to source control, a mobile build, or a request from the client.

Set the backend environment variables `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` in the deployment dashboard. Then verify the deletion endpoint with an authenticated test account in a non-production Supabase project before enabling it for users. The server key is not present in `render.yaml` values; `sync: false` requires an operator to set it in the provider dashboard.

Deletion spans Supabase Auth and optional Firestore, which do not share a transaction. A failure after Firestore cleanup may leave server-side deletion partially complete. The app now distinguishes known pre-deletion configuration failures from unconfirmed outcomes, clears sensitive in-memory state as soon as the server confirms deletion, attempts each local store cleanup independently, and reports incomplete local cleanup separately. Check server logs before retrying an unconfirmed deletion. The operation removes records belonging to the verified account only. Data held by third-party LLM providers is outside this endpoint and may follow their retention policies.

## Storage caveat

With the explicit memory opt-in, event arrays are process-local, bounded, and disappear on restart; use only for local/evaluation runs, never as durable production storage. Without Firestore or that explicit opt-in, health-data reads/writes and account deletion fail closed with HTTP 503. Firestore write failures return 503 without keeping a misleading RAM copy or exposing the provider exception. Configure and review durable storage, access controls, retention, backups, monitoring, and deletion behavior before enabling health-data sync. The public `/health` route intentionally returns only a liveness status.
