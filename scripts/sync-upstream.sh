#!/usr/bin/env bash
#
# sync-upstream.sh — pull the latest upstream CLIProxyAPI into KorpProxy.
#
# Creates a sync branch off main, merges upstream/main, then runs gofmt +
# build + tests. Leaves the branch checked out for review; it does NOT push.
# Open a PR with `git push -u origin <branch>` once you're happy, or let the
# fork-sync GitHub Action do it for you.
#
# Conflicts: resolve them in place, then `git add -A && git commit --no-edit`.
# git rerere is enabled, so each resolution is remembered and auto-applied on
# the next sync.
set -euo pipefail

UPSTREAM_REMOTE="${UPSTREAM_REMOTE:-upstream}"
BASE_BRANCH="${BASE_BRANCH:-main}"
# What to merge. By default we track the latest upstream *release* tag (matching
# the fork-sync Action). Override with UPSTREAM_REF=upstream/main for bleeding edge,
# or UPSTREAM_REF=v7.1.40 to pin a specific tag.
UPSTREAM_REF="${UPSTREAM_REF:-}"

cd "$(git rev-parse --show-toplevel)"

# Make repeated conflict resolutions automatic.
git config rerere.enabled true
git config rerere.autoupdate true

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "✖ Working tree is dirty — commit or stash before syncing." >&2
  exit 1
fi

echo "▸ Fetching ${UPSTREAM_REMOTE} (with tags)…"
git fetch --tags "${UPSTREAM_REMOTE}"

# Resolve the ref to merge: latest release tag unless the caller pinned one.
if [ -z "${UPSTREAM_REF}" ]; then
  UPSTREAM_REF="$(git -c 'versionsort.suffix=-' tag -l 'v*' --sort=-v:refname | head -1)"
  if [ -z "${UPSTREAM_REF}" ]; then
    echo "✖ Could not find any upstream release tag (v*)." >&2
    exit 1
  fi
fi
echo "▸ Target upstream ref: ${UPSTREAM_REF}"

if git merge-base --is-ancestor "${UPSTREAM_REF}" "${BASE_BRANCH}"; then
  echo "✓ Already up to date with ${UPSTREAM_REF}."
  exit 0
fi

SYNC_BRANCH="sync/upstream-$(date -u +%Y%m%d-%H%M%S)"
echo "▸ Creating ${SYNC_BRANCH} from ${BASE_BRANCH}…"
git checkout -B "${SYNC_BRANCH}" "${BASE_BRANCH}"

echo "▸ Merging ${UPSTREAM_REF}…"
if ! git merge --no-edit "${UPSTREAM_REF}"; then
  echo
  echo "✖ Merge conflicts in:"
  git diff --name-only --diff-filter=U | sed 's/^/    - /'
  echo
  echo "  Resolve them, then:  git add -A && git commit --no-edit"
  echo "  (rerere will remember the resolution for next time.)"
  exit 2
fi

echo "▸ gofmt check…"
unformatted="$(gofmt -l . || true)"
if [ -n "${unformatted}" ]; then
  echo "✖ gofmt needed on:"
  echo "${unformatted}" | sed 's/^/    - /'
  exit 3
fi

echo "▸ Building (go build ./cmd/server)…"
go build -o /tmp/korpproxy-server ./cmd/server
rm -f /tmp/korpproxy-server

echo "▸ Testing (go test ./...)…"
go test ./...

echo
echo "✓ Clean sync on ${SYNC_BRANCH}."
echo "  Open a PR with:   git push -u origin ${SYNC_BRANCH}"
echo "  Or merge locally: git checkout ${BASE_BRANCH} && git merge --ff-only ${SYNC_BRANCH}"
