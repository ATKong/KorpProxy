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
>>>>>>> v7.2.96

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

<<<<<<< HEAD
See [FORK.md](FORK.md) for the full fork documentation — layout, remotes,
sync automation, core-fix conventions, and the model-catalog schema.
=======
### [ProxyPilot](https://github.com/Finesssee/ProxyPilot)

Windows-native CLIProxyAPI fork with TUI, system tray, and multi-provider OAuth for AI coding tools - no API keys needed.

### [Claude Proxy VSCode](https://github.com/uzhao/claude-proxy-vscode)

VSCode extension for quick switching between Claude Code models, featuring integrated CLIProxyAPI as its backend with automatic background lifecycle management.

### [ZeroLimit](https://github.com/0xtbug/zero-limit)

Windows desktop app built with Tauri + React for monitoring AI coding assistant quotas via CLIProxyAPI. Track usage across Gemini, Claude, OpenAI Codex, and Antigravity accounts with real-time dashboard, system tray integration, and one-click proxy control - no API keys needed.

### [CPA-XXX Panel](https://github.com/ferretgeek/CPA-X)

A lightweight web admin panel for CLIProxyAPI with health checks, resource monitoring, real-time logs, auto-update, request statistics and pricing display. Supports one-click installation and systemd service.

### [CLIProxyAPI Tray](https://github.com/kitephp/CLIProxyAPI_Tray)

A Windows tray application implemented using PowerShell scripts, without relying on any third-party libraries. The main features include: automatic creation of shortcuts, silent running, password management, channel switching (Main / Plus), and automatic downloading and updating.

### [霖君](https://github.com/wangdabaoqq/LinJun)

霖君 is a cross-platform desktop application for managing AI programming assistants, supporting macOS, Windows, and Linux systems. Unified management of Claude Code, Gemini, OpenAI Codex, and other AI coding tools, with local proxy for multi-account quota tracking and one-click configuration.

### [CLIProxyAPI Dashboard](https://github.com/itsmylife44/cliproxyapi-dashboard)

A modern web-based management dashboard for CLIProxyAPI built with Next.js, React, and PostgreSQL. Features real-time log streaming, structured configuration editing, API key management, OAuth provider integration for Claude/Gemini/Codex, usage analytics, container management, and config sync with OpenCode via companion plugin - no manual YAML editing needed.

### [All API Hub](https://github.com/qixing-jk/all-api-hub)

Browser extension for one-stop management of New API-compatible relay site accounts, featuring balance and usage dashboards, auto check-in, one-click key export to common apps, in-page API availability testing, and channel/model sync and redirection. It integrates with CLIProxyAPI through the Management API for one-click provider import and config sync.

### [Shadow AI](https://github.com/HEUDavid/shadow-ai)

Shadow AI is an AI assistant tool designed specifically for restricted environments. It provides a stealthy operation
mode without windows or traces, and enables cross-device AI Q&A interaction and control via the local area network (
LAN). Essentially, it is an automated collaboration layer of "screen/audio capture + AI inference + low-friction delivery",
helping users to immersively use AI assistants across applications on controlled devices or in restricted environments.

### [ProxyPal](https://github.com/buddingnewinsights/proxypal)

Cross-platform desktop app (macOS, Windows, Linux) wrapping CLIProxyAPI with a native GUI. Connects Claude, ChatGPT, Gemini, GitHub Copilot, and custom OpenAI-compatible endpoints with usage analytics, request monitoring, and auto-configuration for popular coding tools - no API keys needed.

### [CLIProxyAPI Quota Inspector](https://github.com/AllenReder/CLIProxyAPI-Quota-Inspector)

Ready-to-use cross-platform quota inspector for CLIProxyAPI, supporting per-account codex 5h/7d quota windows, plan-based sorting, status coloring, and multi-account summary analytics.

### [CLIProxy Pool Watch](https://github.com/murasame612/CLIProxyPoolWidget)

Native macOS SwiftUI app for monitoring ChatGPT/Codex account quotas in CLIProxyAPI pools. Displays account availability, Plus-base capacity, 5-hour and weekly quota bars, plan weights, and restore forecasts through the Management API.

### [Panopticon](https://github.com/eltmon/panopticon-cli)

Multi-agent orchestration for AI coding assistants. Runs CLIProxyAPI as a local sidecar so its agents can drive GPT models through a ChatGPT subscription, pointing Claude Code at an Anthropic-compatible endpoint with no OpenAI API key required.

### [Tunnel Agent](https://github.com/Villoh/tunnel-agent)

Windows desktop UI that manages CLIProxyAPI and Perplexity WebUI Scraper from a single interface, inspired by Quotio and VibeProxy. Connect OAuth providers (Claude, Gemini, Codex, Kimi, Antigravity), custom API keys, and Perplexity session accounts, then point any coding agent at the local endpoint.

### [Quotio Desktop](https://github.com/xiaocoss/quotio-desktop)

Cross-platform (Tauri) port of Quotio for Windows, macOS and Linux. Manages a pool of AI accounts (Codex, Claude Code, GitHub Copilot, Gemini, Antigravity, Kiro, Cursor, Trae, GLM) through CLIProxyAPI, with per-account 5-hour/weekly quota bars, Codex rate-limit reset credits with one-click reset, smart scheduling, usage statistics, and multi-instance Codex — no API keys needed.

### [Universal Chat Provider](https://github.com/maxdewald/vscode-universal-chat-provider)

VS Code extension that brings your Claude, ChatGPT/Codex, Antigravity, Grok, and Kimi subscriptions into GitHub Copilot Chat as native language models — and can power your Git commit messages, chat titles, and summaries too. Runs CLIProxyAPI in a fully managed background lifecycle (download, verify, supervise) shared across all windows, so it's zero-setup. No API keys needed, just OAuth.

### [CPA-Tray-Powershell](https://github.com/IQ-Director/CPA-Tray-Powershell)

A PowerShell-based Windows system tray launcher for CLIProxyAPI. It supports running in the background without a console window, opening the management page, keeping the backend running after the management window closes, and reopening the page from the tray. It also supports checking for CLIProxyAPI updates on startup, SHA-256 verification with rollback, one-click CLIProxyAPI restart and update, PID-validated process management, and safe service shutdown.

### [Grok Search MCP](https://github.com/MapleMapleCat/Grok_Search_Mcp)

An HTTP-only Model Context Protocol server that uses a CLIProxyAPI deployment to provide Grok-powered real-time web search, X/Twitter search, and model discovery to MCP clients. It adds MCP transport, client API-key management, quotas, usage tracking, and a web administration panel.

### [AIUsage](https://github.com/sylearn/AIUsage)

Native macOS SwiftUI dashboard for AI subscriptions and coding proxies. It manages official CLIProxyAPI releases end to end (download, verify, supervise, update, and roll back), unifies OAuth accounts and live models, and connects one gateway to Codex, Claude Code/Science, OpenCode, or OpenAI/Anthropic/Gemini clients, with optional LAN access.

> [!NOTE]  
> If you developed a project based on CLIProxyAPI, please open a PR to add it to this list.

## More choices

Those projects are ports of CLIProxyAPI or inspired by it:

### [9Router](https://github.com/decolua/9router)

A Next.js implementation inspired by CLIProxyAPI, easy to install and use, built from scratch with format translation (OpenAI/Claude/Gemini/Ollama), combo system with auto-fallback, multi-account management with exponential backoff, a Next.js web dashboard, and support for CLI tools (Cursor, Claude Code, Cline, RooCode) - no API keys needed.

### [OmniRoute](https://github.com/diegosouzapw/OmniRoute)

Never stop coding. Smart routing to FREE & low-cost AI models with automatic fallback.

OmniRoute is an AI gateway for multi-provider LLMs: an OpenAI-compatible endpoint with smart routing, load balancing, retries, and fallbacks. Add policies, rate limits, caching, and observability for reliable, cost-aware inference.

### [Playful Proxy API Panel (PPAP)](https://github.com/daishuge/playful-proxy-api-panel)

A public CLIProxyAPI-compatible fork and bundled management panel. It keeps upstream-style usage while restoring built-in usage statistics, adding cache hit rate, first-byte latency, TPS tracking, and Docker-oriented self-hosted installation docs.

### [Codex Switch](https://github.com/9ycrooked/CodexSwitch)

This is a tool built with Tauri 2 + Vue 3 for managing multiple OpenAI Codex desktop accounts. Switch between saved ChatGPT/Codex certification profiles, check 5-hour and weekly quota usage in real time, verify token health, view active account details, and import or save auth.json files without manual copying.

> [!NOTE]  
> If you have developed a port of CLIProxyAPI or a project inspired by it, please open a PR to add it to this list.
>>>>>>> v7.2.96

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE)
file for details.
