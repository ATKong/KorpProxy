# KorpProxy

English | [中文](README_CN.md) | [日本語](README_JA.md)

**KorpProxy** is a maintained fork of
[router-for-me/CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI)
bundled with a native **macOS menu-bar app**. The fork tracks upstream's
(near-daily) releases automatically while letting us land core fixes and new
models on our own schedule.

All credit for the underlying proxy engine goes to the upstream
[CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI) authors and
maintainers. KorpProxy adds the macOS app, automated upstream syncing, and a
self-controlled model catalog on top.

## What the engine does

The engine at the repo root is an exact mirror of upstream's Go proxy server.
It exposes OpenAI / Gemini / Claude / Codex / Grok compatible API endpoints so
you can drive your CLI subscriptions (or API keys) from any compatible client
or SDK:

- OpenAI (including Responses), Gemini, Claude, and Grok compatible endpoints
- OpenAI Codex (GPT models) and Claude Code support via OAuth login
- OAuth credential management with simple CLI authentication flows
- Round-robin load balancing across multiple accounts and keys
  (Gemini, OpenAI, Claude, Codex, Grok)
- Streaming, non-streaming, and WebSocket responses where supported
- Function calling / tools and multimodal (text + image) input
- OpenAI-compatible upstream providers via config (e.g. OpenRouter)
- Generative Language API key support
- Reusable Go SDK for embedding the proxy (see `docs/sdk-usage.md`)

Upstream guides and the Management API reference live at
[https://help.router-for.me/](https://help.router-for.me/).

## macOS app

The `app/` directory holds **KorpProxy.app**, a native SwiftUI menu-bar app
(`MenuBarExtra`) that supervises the Go engine on macOS:

- Launches, stops, restarts, and health-checks the engine process
- Manages engine files under `~/Library/Application Support/KorpProxy/`
  (config.yaml, auths, logs)
- Talks to the engine's `/v0/management` API and shows a live log tail in
  Settings
- Ships Sparkle-based auto-update

The app is unsandboxed (it spawns the engine and binds a local port) and is not
intended for the Mac App Store. See [`app/README.md`](app/README.md) for build
and run details.

## Quick start

### Build & run the engine

```bash
go build -o cli-proxy-api ./cmd/server   # build
go run ./cmd/server                      # run a dev server
```

Common flags: `--config <path>`, `--tui` (terminal UI), `--standalone`,
`--local-model`, `--no-browser`.

### Configure

Copy the example config and edit it:

```bash
cp config.example.yaml config.yaml
```

The server reads `config.yaml` by default (override with `--config`). A `.env`
file in the working directory is auto-loaded, and auth material defaults to
`auths/`. When a config snippet needs an API key, use a placeholder such as
`YOUR_API_KEY` rather than a real secret.

### Docker

```bash
docker compose up -d
```

`docker-compose.yml` maps the engine ports and mounts your `config.yaml`,
`auths/`, and `logs/` into the container. Override paths and the image via the
`CLI_PROXY_CONFIG_PATH`, `CLI_PROXY_AUTH_PATH`, `CLI_PROXY_LOG_PATH`, and
`CLI_PROXY_IMAGE` environment variables.

## Fork specifics

### Automated upstream sync

A GitHub Action (`fork-sync`) runs **every 3 hours** and tracks upstream's
[releases](https://github.com/router-for-me/CLIProxyAPI/releases), merging the
latest published release tag into ours:

| Outcome | What happens |
|---------|--------------|
| Clean merge **and** build + test pass | auto-merges straight to `main` — no PR, no human step |
| Clean merge but build/test **fails** | opens a `sync/upstream-*` PR titled `build/test FAILED` |
| Merge **conflict** | commits the conflicted tree and opens a **draft** PR listing the files |

The steady state is zero manual work; you only get a PR when something needs a
human. For manual syncs use `./scripts/sync-upstream.sh`.

### Self-controlled model catalog (`KORP_MODELS_URL`)

Models are embedded at build time but refreshed from a remote catalog on
startup and every 3 hours — upstream's list by default. KorpProxy adds an
override: set `KORP_MODELS_URL` to one or more comma-separated `models.json`
URL(s) and they're tried first, with upstream kept as fallback.

```bash
export KORP_MODELS_URL=https://example.com/your/models.json
```

`--local-model` disables remote refresh and pins to the embedded list.

See [FORK.md](FORK.md) for the full fork documentation — layout, remotes,
sync automation, core-fix conventions, and the model-catalog schema.

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE)
file for details.
