# Releasing SpacialShell

SpacialShell ships outside the Mac App Store (#20 is closed): a Developer ID signed, notarised,
stapled DMG on a GitHub Release (#16), which installed copies update from through Sparkle (#58).

| Workflow | Runs on | Does |
|---|---|---|
| `.github/workflows/ci.yml` | every push and pull request | `swift build` + the fast gate (Kit, Protocol, UI; not the AX suites). Story snapshots run in a separate, non-blocking step |
| `.github/workflows/release.yml` | a `v*` tag, or by hand (Actions → Release → Run workflow) | tests, DMG, sign + notarise + staple, Sparkle appcast, GitHub Release |
| `.github/workflows/milestone-release.yml` | closing a milestone | tags the next minor version and dispatches `release.yml` on it |

## Version scheme

Tags are `vMAJOR.MINOR.PATCH`, and the tag is the version: `package-dmg.sh` strips the `v` and
`bundle.sh` writes it into both `CFBundleShortVersionString` and `CFBundleVersion`, which is what
Sparkle compares.

- **Closing a milestone** bumps MINOR: the latest `vX.Y.Z` becomes `vX.(Y+1).0`, tagged on the
  default branch's head. Milestone names (`M3c`, `M4`) do not enter into it, so sub-milestones
  work. The latest tag today is `v0.1.0`, so the next milestone closed ships `v0.2.0`.
- **A patch release** is a tag you push yourself: `git tag v0.2.1 && git push origin v0.2.1`.
- **MAJOR** moves when you decide it does (`v1.0.0`, pushed by hand); later milestones bump from it.
- A run dispatched on a branch rather than a tag is versioned `0.1.0-<run number>` and produces an
  artifact only, not a release.

## Secrets

Settings → Secrets and variables → Actions → New repository secret. Every one is optional; the
release degrades, with a warning in the run, rather than failing:

| Secret | What | Without it |
|---|---|---|
| `DEVELOPER_ID_P12` | the Developer ID Application certificate **and private key**, as a base64 .p12 | ad-hoc signed DMG, as before |
| `DEVELOPER_ID_P12_PASSWORD` | the password the .p12 was exported with | (needed with the above) |
| `ASC_KEY_P8` | an App Store Connect API key (.p8), base64 | signed but not notarised |
| `ASC_KEY_ID` | that key's Key ID | (needed with the above) |
| `ASC_ISSUER_ID` | the team's Issuer ID | (needed with the above) |
| `SPARKLE_ED_PRIVATE_KEY` | the Sparkle EdDSA private key (the exported file's contents, as is) | no `appcast.xml`, so installed copies do not see the release |

### Exporting the Developer ID as a .p12

Export the certificate `Scripts/sign-identity` pins. This Mac has two Developer ID Application
certificates, and a DMG signed by the other would not keep the Accessibility grant of copies built
here.

1. `security find-identity -v -p codesigning` and find the pinned SHA-1
   (the hash in your local `Scripts/sign-identity`).
2. Keychain Access → login → My Certificates → **Developer ID Application: <your name> (<TEAM_ID>)**
   with that SHA-1 (select it, ⌘I, check "SHA-1" under Fingerprints). Expand it to confirm the
   private key is underneath.
3. Right-click the certificate → Export… → format **Personal Information Exchange (.p12)** → save as
   `~/Desktop/devid.p12` and choose a strong password.
4. Upload it without it touching the clipboard or the terminal's scrollback, then delete the file:

   ```sh
   base64 -i ~/Desktop/devid.p12 | gh secret set DEVELOPER_ID_P12
   gh secret set DEVELOPER_ID_P12_PASSWORD      # prompts; paste the password
   rm -P ~/Desktop/devid.p12
   ```

The job imports it into a throwaway keychain (`$RUNNER_TEMP/signing.keychain-db`), adds Apple's
Developer ID G2 intermediate, and deletes the keychain when the job ends, pass or fail.

### Creating the App Store Connect API key

1. https://appstoreconnect.apple.com/access/integrations/api → Team Keys → Generate API Key
   (the Account Holder may first have to request API access). Name it `SpacialShell notary`, access
   **Developer**, which is enough for notarytool.
2. Note the **Issuer ID** (above the table) and the key's **Key ID**, then Download API Key. It
   downloads once only — `AuthKey_<KEYID>.p8`.
3. Upload:

   ```sh
   base64 -i ~/Downloads/AuthKey_XXXXXXXXXX.p8 | gh secret set ASC_KEY_P8
   gh secret set ASC_KEY_ID --body XXXXXXXXXX
   gh secret set ASC_ISSUER_ID --body xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
   ```

Keep the .p8 somewhere safe (a password manager) or revoke and regenerate if lost.

For **local** notarisation store the same key, or an Apple ID with an app-specific password, as a
keychain profile once, and name it with `NOTARY_PROFILE`:

```sh
xcrun notarytool store-credentials spacial-notary \
  --key ~/Downloads/AuthKey_XXXXXXXXXX.p8 --key-id XXXXXXXXXX --issuer <issuer-id>
NOTARY_PROFILE=spacial-notary Scripts/notarize.sh --require-notarization
```

`notarize.sh` makes two submissions (#152): first the app, whose ticket it staples onto
`build/SpacialShell.app` before `package-dmg.sh --dmg-only` wraps it, then the DMG, which gets its
own ticket. A copy dragged out of the DMG (or installed by `brew install --cask`) therefore passes
Gatekeeper offline on first launch; `xcrun stapler validate` on the app inside the mounted DMG is
the last check the script runs.

`Scripts/notarize.sh` also takes the key directly: `ASC_KEY_PATH`, `ASC_KEY_ID`, `ASC_ISSUER_ID`.
With no credentials it signs everything, prints Gatekeeper's verdict (`rejected`, "Unnotarized
Developer ID"), and says `notarisation skipped: no credentials`; it exits non-zero only when given
`--require-notarization`. A rejected submission fails loudly with Apple's log.

### The Sparkle key

Done (2026-09-26, #58). The keypair lives in the login keychain of the maintainer's Mac, the public
half is `SUPublicEDKey` in `Resources/Info.plist`, and the private half is the
`SPARKLE_ED_PRIVATE_KEY` secret. Public key:

```
gVEXSYsbwK1VxXKWNyO024bD7E7iuOGJ4w2zgGx/rjA=
```

To redo it (a new Mac, a rotated key), on the Mac holding the key:

```sh
Scripts/sparkle-keys.sh --upload-secret
```

It creates the EdDSA keypair in the login keychain with Sparkle's `generate_keys` (or reuses the one
already there), writes the **public** key into `Resources/Info.plist` as `SUPublicEDKey` — commit
that change — and pipes the **private** key straight into the `SPARKLE_ED_PRIVATE_KEY` secret.
Drop `--upload-secret` to only do the first two. The private key is never printed or written into
the repo; the export it uploads from is an owner-only temp file, overwritten and removed at once.
Back up the keychain item "Private key for signing Sparkle updates" (account `ed25519`): lose it and
every installed copy is stranded on its current version. Rotating it strands them too, since each
copy trusts only the key it shipped with.

The app only starts its updater when it is running as an `.app` **and** Info.plist carries
`SUPublicEDKey`. Releases up to v0.2.1 were built without it, so they never check for updates:
those installs need one manual update (`brew upgrade --cask spacialshell`, or the DMG) onto a
release that carries the key, and self-update from then on. Dev bundles (`bundle.sh` without a
version, e.g. the pre-commit install) drop the key so they never offer to replace themselves with a
release; `SPACIAL_UPDATES=1 Scripts/bundle.sh` keeps it, to try the updater locally.

## Cutting a release

1. Close the milestone on GitHub. `milestone-release.yml` tags the next minor version and starts
   `release.yml`. (Or push a tag yourself for a patch, or run Release by hand on a tag.)
2. Watch Actions → Release. Its warnings say what was skipped for lack of a secret.
3. The release gets `SpacialShell-X.Y.Z.dmg` and, with the Sparkle key, `appcast.xml` (one item,
   the DMG, with its `sparkle:edSignature`; the step fails if the signature is missing). Installed
   copies read `https://github.com/AskAlice/SpacialShell-MacOS/releases/latest/download/appcast.xml`
   once a day, or on "Check for Updates…" in Settings → General.

## Known limits

- Unverified until a real update runs: that the Accessibility grant survives Sparkle replacing the
  bundle (it should — the designated requirement keys on the team ID), and that the relaunch
  restores parked windows (it goes through `applicationWillTerminate`, like a quit).
- CI story snapshots are non-blocking until they prove stable on hosted runners (#53); drop
  `continue-on-error` in `ci.yml` once they do.
