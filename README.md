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

<<<<<<< HEAD
## What the engine does
=======
<table>
<tbody>
    <tr>
        <th align="center" width="100">Provider</th>
        <th align="center">Description</th>
    </tr>
    <tr>
        <td align="center"><a href="https://www.kimi.com/code/?aff=cliproxyapi"><img src="./assets/logo/kimi.svg" alt="Kimi" width="28" height="28" /></a></td>
        <td>Kimi series models (Kimi K3, Kimi K2.7 Code, etc.). <a href="https://platform.kimi.ai/docs/guide/kimi-k3-quickstart">Kimi K3</a> is Moonshot AI’s most capable model and the world’s first open 3T-class model. With 2.8 trillion parameters, native vision, and a 1-million-token context window, K3 is built for long-horizon coding, knowledge work, and reasoning. CLIProxyAPI supports Kimi through OAuth or compatible API interfaces. Try the <a href="https://www.kimi.com/code/?aff=cliproxyapi">Kimi Code subscription</a>, or get an API key from the <a href="https://platform.kimi.ai/?aff=cliproxyapi">Kimi Open Platform</a>. Thanks to Kimi for supporting CLIProxyAPI and the open-source community!</td>
    </tr>
    <tr>
        <td align="center"><a href="https://platform.openai.com/docs/guide/gpt-5.6"><img src="./assets/logo/openai.svg" alt="OpenAI" width="28" height="28" /></a></td>
        <td>OpenAI GPT series models (GPT 5.6, GPT 5.5, etc.). GPT-5.6 sets a new quality and efficiency baseline for complex production workflows. GPT-5.6 is especially token-efficient and improves frontend aesthetics, including layout, visual hierarchy, and design judgment.</td>
    </tr>
    <tr>
        <td align="center"><a href="https://www.anthropic.com/claude/fable"><img src="./assets/logo/claude.svg" alt="Anthropic" width="28" height="28" /></a></td>
        <td>Anthropic Claude series models (Claude Fable, Claude Opus, Claude Sonnet, etc.). Claude Fable 5 is Anthropic's most capable widely released model, built for the most demanding reasoning and long-horizon agentic work.</td>
    </tr>
    <tr>
        <td align="center"><a href="https://antigravity.google/"><img src="./assets/logo/antigravity.svg" alt="Antigravity" width="28" height="28" /></a></td>
        <td>Google Gemini series models (Gemini 3.5 Flash, Gemini 3.1 Pro, etc.). Gemini 3.5 Flash provides sustained frontier-level intelligence optimized for real-world tasks at a higher speed and lower cost. Designed for the agentic era, it excels at sub-agent deployment, multi-step workflows, and long-horizon tasks at scale. This model is particularly effective for rapid agentic loops involving complex coding cycles and iterations.</td>
    </tr>
    <tr>
        <td align="center"><a href="https://x.ai/grok"><img src="./assets/logo/xai.svg" alt="xAI" width="28" height="28" /></a></td>
        <td>xAI Grok series models (Grok 4.5, Grok Composer 2.5 Fast, etc.). Grok 4.5 is SpaceXAI's frontier model built for coding, agentic tasks, and knowledge work. It was trained in SpaceXAI's data centers in Memphis with new datasets spanning science, engineering, and math.</td>
    </tr>
</tbody>
</table>
>>>>>>> v7.2.94

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
