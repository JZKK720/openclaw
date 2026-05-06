# Docker Guide

Scope

- Applies to `scripts/docker/**`, root `docker-compose.yml`, root `Dockerfile`, root `.env.example`, and `scripts/clawdock/**` when the bundled Docker flow changes.

Read first

- `docs/install/docker.md` for the user-facing container flow and host-provider caveats.
- `docs/providers/ollama.md` for Ollama auth, native URL rules, and manual-vs-discovery config choices.
- `scripts/clawdock/README.md` when touching helper UX or host-side Docker workflows.

Compose rules

- Keep the container listen ports fixed at `18789` (gateway) and `18790` (bridge). Host-side overrides belong in repo `.env` via `OPENCLAW_GATEWAY_PORT` and `OPENCLAW_BRIDGE_PORT`.
- If a user wants the local Gateway UI on `18788`, set `OPENCLAW_GATEWAY_PORT=18788`. Do not rewrite the container command, healthcheck, or internal gateway port unless the runtime contract itself changes.
- Repo `.env` is Docker infra only. Secrets belong in `~/.openclaw/.env`. Runtime behavior belongs in `~/.openclaw/openclaw.json`.
- `openclaw-cli` shares the gateway network namespace and is a post-start tool. Pre-start onboarding or config writes must run through `openclaw-gateway` with `--no-deps --entrypoint node`.
- Keep Control UI allow-origins aligned with the published host port. `scripts/docker/setup.sh` already seeds `gateway.controlUi.allowedOrigins` from `OPENCLAW_GATEWAY_PORT`; manual flows must do the same.

Ollama in Docker

- Inside the container, host Ollama is `http://host.docker.internal:11434`, not `http://127.0.0.1:11434`.
- Use the native Ollama base URL only. Never append `/v1`.
- Docker onboarding defaults to `http://host.docker.internal:11434` because `scripts/docker/setup.sh` exports `OPENCLAW_DOCKER_SETUP=1`.
- For host-backed Ollama, use `api: "ollama"` and `apiKey: "ollama-local"`.
- Do not rely on env-only Ollama auto-discovery inside Docker; onboarding or explicit provider config must pin the Docker-reachable base URL.
- When a user names a local model, prefer the exact pulled tag from `ollama list` or `openclaw models list --provider ollama`. Example: `ollama/nemotron3:33b-q8`.
- Prefer onboarding or `openclaw models set ollama/<exact-model>` for model selection. Only write `models.providers.ollama.models` manually when you intentionally disable discovery for a custom host, port, or curated model list.
- Large local models may need `timeoutSeconds`, aligned `contextWindow` and `params.num_ctx`, and optional `keep_alive` when you write explicit provider entries.

Windows Docker Desktop

- Keep the `host.docker.internal:host-gateway` mapping in Compose. Do not replace it with transient WSL or NAT gateway IPs.
- Validate the published host URL from Windows with `http://127.0.0.1:<OPENCLAW_GATEWAY_PORT>`.

Validation

- `docker compose config`
- `docker compose up -d openclaw-gateway`
- `docker compose ps`
- `Invoke-WebRequest http://127.0.0.1:<host-port>/healthz` on Windows, or `curl -fsS` on POSIX.
- `docker compose run --rm openclaw-cli models list --provider ollama` after the gateway is up.