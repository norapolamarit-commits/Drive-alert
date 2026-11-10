# doz Cloud API

## Local run

```sh
cd /Users/norapol/Downloads/Doz/app/cloud_api
python3.11 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
uvicorn main:app --reload --host 127.0.0.1 --port 8000
```

The Render blueprint pins Python to 3.11.16 (`PYTHON_VERSION`) to avoid inheriting different platform defaults. Use the same Python version for local development and API tests. Do not rely on Python 3.9, which is end-of-life and produced compatibility warnings in the previous local test run.

Configure `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` for authenticated routes. The mobile app must receive only the public/publishable key, never an admin key. Configure `LLM_API_KEY` on the server to enable generated replies; without it, `/chat` returns an explicitly labeled knowledge/fallback response rather than claiming that an LLM answered.

The `/chat` route accepts a question up to 2,000 characters and a composed prompt up to 10,000 characters. The server selects its model from `LLM_MODEL`; a model name supplied by the mobile client is ignored. Authenticated `/chat` and `/advice` requests share a per-account process-local limit (defaults: 20 total AI requests per 60 seconds), and AI work across both routes is capped at two concurrent requests. Override these defaults with `AI_RATE_LIMIT_MAX`, `AI_RATE_LIMIT_WINDOW_SECONDS`, and `AI_MAX_CONCURRENT_REQUESTS`. These in-memory safeguards reset on restart and are not shared across replicas; configure a shared gateway/provider rate limit and abuse monitoring before public or multi-instance production deployment.

Health-data routes (`GET/POST /sensor`, `GET/POST /alert`, and `GET /devices`) fail closed with HTTP 503 unless `HEALTH_DATA_SYNC_ENABLED=true` is set on the server. The deployment manifest sets it to `false`; do not enable it until retention, account isolation, deletion, access controls, and shared rate limiting have been reviewed and tested. Chat/advice remain separate and can be enabled without turning on health-data storage.

`/advice` accepts only bounded `status` (1–80 characters), `alertLevel` (up to 40), and `sensor` text (up to 2,000 characters). Extra client fields are ignored, and the server always selects `LLM_MODEL`; callers cannot override the provider model.

Before connecting the app, verify `GET https://<deployed-host>/health` returns `200` and `{"status":"ok"}`. Then test both `/chat` and `/advice` using a non-production Supabase account and verify their response modes (`llm`/`fallback` and `rag`/`fallback`, respectively) and that invalid/expired tokens are rejected on both routes. Configure the app with that exact HTTPS host through `VITAGAURD_CLOUD_BASE_URL`; a local API or an unverified host must not be presented as a live AI service.

Use `preflight_chat.py` for a repeatable deployment check. It checks health, authenticated chat, authenticated advice, and rejection of a fake token on both AI routes. Supply a short-lived access token from a non-production test account through the environment; never put it in a source file or command history. The test requests contain no sensor or profile data, but if the server is configured for LLM mode they will be sent to the configured external model provider. The default accepts explicitly identified fallback modes; pass `--require-llm` to require actual LLM responses from both routes.

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

Current deployment check (10 November 2026, 20:59 Asia/Bangkok): the example host `https://vita-gaurd-cloud-api.onrender.com/health` returned HTTP 404 (`Not Found`, `x-render-routing: no-server`). Treat it as **not deployed/not available**; do not package this URL as a working chatbot endpoint. The Render service name in `render.yaml` matches the hostname, so this is not a service-name spelling mismatch. A deployment operator must create or repair the Render web service from `app/cloud_api/render.yaml`, set its required secrets in the provider dashboard, and repeat the health/chat/advice preflight before using the URL in an app build. Local backend regression tests passed 31 tests using mocked Auth/provider calls; this does not prove a live deployment. The preflight script and its tests also run under the host's Python 3.9 after replacing Python 3.10-only union syntax with `typing.Optional`. No deployment or external configuration change has been made by this repository check.

Provider/model check (10 November 2026): Hugging Face's official public model API returned an empty `inferenceProviderMapping` for the configured model `nectec/Pathumma-llm-text-1.0.0`; merely setting `LLM_API_KEY` therefore does not establish that generated replies will work, and the API may return its explicit fallback. A separate official metadata query returned `KBTG-Labs/THaLLE-0.2-ThaiLLM-8B-fa` mapped to Featherless with `status=live` and task `conversational` at check time. This is only an alternative to review, not an approved model change or proof of a successful inference call. Verify provider/model availability and privacy/cost terms before changing; then require `preflight_chat.py --require-llm` to pass against the deployed service. These mappings can change. Hugging Face documents `inferenceProviderMapping` as the source for checking live providers: <https://huggingface.co/docs/inference-providers/hub-api#get-model-providers>.

### Render Blueprint setup

This is a monorepo: the Git repository root is `Doz/`, while the API and blueprint are under `app/cloud_api/`. When creating the Blueprint in Render, set **Blueprint Path** to `app/cloud_api/render.yaml`. The service definition sets `rootDir: app/cloud_api`, so the pip install and Uvicorn commands run in the directory containing `requirements.txt` and `main.py`. The Blueprint uses Render's current `runtime: python` field and checks `/health` after deploy. Do not create a second service from a different Blueprint path for the same API.

The three `sync: false` variables in the Blueprint must be entered in Render's protected environment settings: `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, and `SUPABASE_SERVICE_ROLE_KEY`; add `LLM_API_KEY` to enable generated chat replies. Keep the admin key server-side only. The `free` plan may sleep when idle and is only suitable for evaluation; verify latency and plan limits before relying on it for time-sensitive alerts.

## Account deletion

`DELETE /account` verifies the caller's Supabase bearer token, obtains the user ID from Supabase (the client cannot choose it), removes that user's API/Firestore sensor and alert records, then calls the Supabase Admin Users API to delete the account. The route fails closed with HTTP 503 when `SUPABASE_SERVICE_ROLE_KEY` is absent. Configure this secret only in the server's protected environment (for example Render's service environment); do not put it in `.env` committed to source control, a mobile build, or a request from the client.

Set the backend environment variables `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` in the deployment dashboard. Then verify the deletion endpoint with an authenticated test account in a non-production Supabase project before enabling it for users. The server key is not present in `render.yaml` values; `sync: false` requires an operator to set it in the provider dashboard.

Deletion spans Supabase Auth and optional Firestore, which do not share a transaction. If persistent event deletion or Supabase deletion fails, the endpoint returns an error and the app does not clear local account data; retry or investigate server logs. The operation removes records belonging to the verified account only. Data held by third-party LLM providers is outside this endpoint and may follow their retention policies.

## Storage caveat

Without Firestore, event arrays are in process memory and disappear on restart; this is not durable production storage. Configure and review a durable database, access controls, retention, backups, monitoring, and deletion behavior before enabling health-data sync. The public `/health` route intentionally returns only a liveness status.
