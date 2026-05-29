# Releasing KorpProxy

Two independent pipelines, triggered by different git tags on the private
`ATKong/KorpProxy` repo:

| What | Tag | Workflow | Output |
| --- | --- | --- | --- |
| **macOS app** (Sparkle auto-update) | `app-vX.Y.Z` | `.github/workflows/app-release.yml` | signed+notarized `KorpProxy-X.Y.Z.dmg` (drag-to-Applications) + `KorpProxy-X.Y.Z.zip` (Sparkle) + `appcast.xml` → public `ATKong/KorpProxy-releases` |
| **Go engine** binaries | `vX.Y.Z` | `.github/workflows/release.yaml` (goreleaser) | per-platform tarballs → private repo Releases |

The app **bundles** the engine, so a normal user only ever needs app updates;
the engine tarballs are for headless/CLI use.

## Auto-update architecture (app)

- Sparkle is added via SPM in `app/project.yml`; `UpdaterManager.swift` drives it.
- `Info.plist` carries `SUFeedURL` → `https://atkong.github.io/KorpProxy-releases/appcast.xml`
  and `SUPublicEDKey` (the EdDSA **public** key).
- Each release uploads a `.dmg` (drag KorpProxy to Applications — what humans
  download) and a `.zip` (the Sparkle update artifact) as GitHub Release assets
  on the **public** `KorpProxy-releases` repo, and prepends an `<item>` to
  `appcast.xml`, which is served from that repo via GitHub Pages.
- The app checks the feed daily (and via the menu "Check for Updates…").

## One-time setup

### 1. Sparkle signing key
Already generated. The **public** key is in `app/project.yml` (`SUPublicEDKey`).
The **private** key was exported to `app/.sparkle_private_key.txt` (gitignored).
Add it as the `SPARKLE_PRIVATE_KEY` repo secret, then delete the local file:

```bash
gh secret set SPARKLE_PRIVATE_KEY < app/.sparkle_private_key.txt
rm app/.sparkle_private_key.txt
```

(To rotate later: `./bin/generate_keys` from the Sparkle tools, update
`SUPublicEDKey` in `project.yml`, and replace the secret.)

### 2. Developer ID certificate (for signing)
Export your **Developer ID Application** cert + private key from Keychain Access
as a `.p12`, then:

```bash
base64 -i DeveloperID.p12 | gh secret set MACOS_CERT_P12_BASE64
gh secret set MACOS_CERT_PASSWORD          # the .p12 export password
gh secret set DEVELOPER_ID_APP             # e.g. "Developer ID Application: Your Name (TEAMID)"
gh secret set MACOS_TEAM_ID                # your 10-char Team ID
```

### 3. Notarization (App Store Connect API key)
Create an API key at https://appstoreconnect.apple.com/access/integrations/api
(role: Developer), download the `.p8`, then:

```bash
base64 -i AuthKey_XXXX.p8 | gh secret set NOTARY_KEY_P8_BASE64
gh secret set NOTARY_KEY_ID                # the key's Key ID
gh secret set NOTARY_ISSUER_ID             # the Issuer ID
```

### 4. Cross-repo publish token
The release job pushes the dmg + zip + appcast to the **public** repo. The
default `GITHUB_TOKEN` can't write cross-repo, so create a **classic** PAT with
the `repo` scope (fine-grained tokens returned 403 on the releases API) and add it:

```bash
gh secret set RELEASES_REPO_TOKEN          # classic repo-scope PAT for KorpProxy-releases
```

## Cutting an app release

```bash
# bump the version in app/project.yml (MARKETING_VERSION), commit, then:
git tag app-v0.2.0
git push origin app-v0.2.0
```

The `app-release` workflow builds, signs, notarizes, staples, zips (for Sparkle),
builds a notarized drag-to-Applications DMG, Sparkle-signs, updates the appcast,
creates the GitHub Release on the public repo, and pushes the updated feed. Existing installs pick it up within a day (or immediately via
"Check for Updates…").

## Cutting an engine release

```bash
git tag v7.1.30-korp.1
git push origin v7.1.30-korp.1
```

## Local dry-run of the app packaging

With your Developer ID + Sparkle key in the login keychain:

```bash
DEVELOPER_ID_APP="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE="my-notary-profile" \
  ./app/scripts/package-app.sh        # → app/dist/KorpProxy-<version>.{dmg,zip} + appcast.xml
```

Omit the notary vars to skip notarization (Gatekeeper will warn on other Macs,
but it's fine for a local smoke test).
