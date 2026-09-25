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
   (`<sign-identity SHA-1>`).
2. Keychain Access → login → My Certificates → **Developer ID Application: Alice Knag (<TEAM_ID>)**
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
xcrun notarytool store-credentials spacialshell-notary \
  --key ~/Downloads/AuthKey_XXXXXXXXXX.p8 --key-id XXXXXXXXXX --issuer <issuer-id>
NOTARY_PROFILE=spacialshell-notary Scripts/notarize.sh --require-notarization
```

`Scripts/notarize.sh` also takes the key directly: `ASC_KEY_PATH`, `ASC_KEY_ID`, `ASC_ISSUER_ID`.
With no credentials it signs everything, prints Gatekeeper's verdict (`rejected`, "Unnotarized
Developer ID"), and says `notarisation skipped: no credentials`; it exits non-zero only when given
`--require-notarization`. A rejected submission fails loudly with Apple's log.

### The Sparkle key

Once, on this Mac:

```sh
Scripts/sparkle-keys.sh --upload-secret
```

It creates the EdDSA keypair in the login keychain with Sparkle's `generate_keys` (or reuses the one
already there), writes the **public** key into `Resources/Info.plist` as `SUPublicEDKey` — commit
that change — and pipes the **private** key straight into the `SPARKLE_ED_PRIVATE_KEY` secret.
Drop `--upload-secret` to only do the first two. The private key is never printed or written into
the repo. Back up the keychain item "Private key for signing Sparkle updates": lose it and every
installed copy is stranded on its current version.

The app only starts its updater when it is running as an `.app` **and** Info.plist carries
`SUPublicEDKey`, so until the script has run, builds behave exactly as before and the settings
window shows no "Check for Updates…" button.

## Cutting a release

1. Close the milestone on GitHub. `milestone-release.yml` tags the next minor version and starts
   `release.yml`. (Or push a tag yourself for a patch, or run Release by hand on a tag.)
2. Watch Actions → Release. Its warnings say what was skipped for lack of a secret.
3. The release gets `SpacialShell-X.Y.Z.dmg` and, with the Sparkle key, `appcast.xml`. Installed
   copies read `https://github.com/AskAlice/SpacialShell-MacOS/releases/latest/download/appcast.xml`
   once a day, or on "Check for Updates…" in Settings → General.

## Known limits

- **The repository is private, so auto-update cannot reach it yet.** Release assets of a private
  repo need an authenticated request, and Sparkle makes anonymous ones: the appcast and the DMG
  both 404 for it. Updates work once releases are public — make the repo public, or publish the
  release assets to a public repo (e.g. `AskAlice/SpacialShell-releases`) and point `SUFeedURL`
  and `--download-url-prefix` in `release.yml` there.
- Only the DMG is notarised and stapled. The app inside is covered by the same ticket (Gatekeeper
  checks it online on first launch); stapling the app itself would take a second submission.
- Unverified until a real update runs: that the Accessibility grant survives Sparkle replacing the
  bundle (it should — the designated requirement keys on the team ID), and that the relaunch
  restores parked windows (it goes through `applicationWillTerminate`, like a quit).
- CI story snapshots are non-blocking until they prove stable on hosted runners (#53); drop
  `continue-on-error` in `ci.yml` once they do.
