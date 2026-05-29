# KorpProxy — fork & app guide

KorpProxy is a **maintained fork** of
[router-for-me/CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI) plus a
native **macOS menu-bar app**. The fork lets us land core fixes and new models
on our own schedule instead of waiting on upstream, while still pulling
upstream's (near-daily) updates.

## Layout

| Path | What | Touched by upstream? |
|------|------|----------------------|
| repo root (`cmd/`, `internal/`, `sdk/`, `go.mod`, …) | The Go engine — an **exact mirror of upstream's tree** | yes — keep it mergeable |
| `app/` | The SwiftUI macOS menu-bar app | no — ours only |
| `scripts/sync-upstream.sh` | Local upstream-sync helper | no |
| `.github/workflows/fork-*.yml` | Our CI (build/test) + weekly upstream sync | no |
| `FORK.md` | This file | no |

**Golden rule:** the engine stays at the repo root so merges from upstream are
trivial. Everything *we* add goes in `app/`, `scripts/`, or `fork-*`-named
files. The only merge conflicts you should ever see come from our own edits to
upstream files (core fixes) — never from app code.

## Remotes

```
origin    https://github.com/ATKong/KorpProxy.git           # our fork
upstream  https://github.com/router-for-me/CLIProxyAPI.git   # the source
```

## Pulling upstream updates

**Automatic:** the `fork-sync` Action runs weekly (and on manual dispatch from
the Actions tab). If upstream merges cleanly it opens a `sync/upstream-*` PR
with build/test status; if it conflicts it files an issue.

**Manual (recommended when there are conflicts):**

```bash
./scripts/sync-upstream.sh        # branch + merge upstream/main + build + test
# resolve any conflicts, then:  git add -A && git commit --no-edit
git push -u origin sync/upstream-<ts>   # open the PR
```

`git rerere` is enabled, so once you resolve a recurring conflict it's replayed
automatically on future syncs.

## Making core fixes

1. Branch off `main`, keep each fix a **small, isolated commit** with a clear
   message (easy to track across merges, easy to drop once upstreamed).
2. Prefer adding **new files** over editing upstream ones where possible — it
   keeps merges clean.
3. **Consider opening the same fix as a PR upstream.** If it lands there, drop
   our patch on the next sync — less to maintain.

## Self-controlled model catalog (`KORP_MODELS_URL`)

Models are defined in `internal/registry/models/models.json` (embedded at build)
but refreshed at runtime from a **remote catalog** on startup and every 3h —
upstream's by default, so new models otherwise appear only when *upstream*
updates their list.

KorpProxy adds an override (`internal/registry/korp_models_source.go`, a file
upstream never touches): set `KORP_MODELS_URL` to one or more comma-separated
`models.json` URL(s) and they're tried first, with upstream kept as fallback.

```bash
export KORP_MODELS_URL=https://example.com/your/models.json
```

Add a model to that catalog and every running instance picks it up within 3h
(or instantly on restart) — no rebuild, no upstream PR. The macOS app will own
this list (serving it locally and/or syncing to a hosted URL). `--local-model`
disables remote refresh and pins to the embedded list.

Per-model schema (from the real Claude Opus 4.8 entry):

```json
{ "id": "claude-opus-4-8", "type": "claude", "owned_by": "anthropic",
  "display_name": "Claude Opus 4.8", "context_length": 1000000,
  "max_completion_tokens": 128000,
  "thinking": { "min": 1024, "max": 128000, "zero_allowed": true,
                "levels": ["low", "medium", "high", "xhigh", "max"] } }
```

## Build

```bash
go build -o /tmp/korpproxy-server ./cmd/server && rm /tmp/korpproxy-server  # compile check
go test ./...                                                              # tests
gofmt -w .                                                                 # format
```

## Disabled upstream workflows

Upstream's own Actions are disabled on this fork (they assume upstream's
process/secrets and would fight our PRs). The files stay in-tree so they don't
cause merge conflicts; they're just turned off in the Actions tab:

- `auto-retarget-main-pr-to-dev.yml` — would retarget our PRs to a `dev` branch
- `agents-md-guard.yml`, `pr-path-guard.yml` — block edits we intentionally make
- `docker-image.yml`, `release.yaml`, `pr-test-build.yml` — upstream build/release

Re-enable any with `gh workflow enable <file> -R ATKong/KorpProxy`.
