# TOML write-back research — a GUI settings window over a hand-edited config.toml (verified 2026-09-12)

Legend: [H]=high, [M]=medium, [L]=low confidence. "Probed" = built and run on this Mac
(macOS 26.5, Swift 6.4 toolchain, `.macOS(.v14)` platform) on 2026-09-12; scratch packages under
`scratchpad/{tkprobe,teprobe}`. Everything else is a pinned upstream source file, a package
manifest, a registry API response, or official project documentation. No secondary write-ups.

---

## The question

SpacialShell's config is TOML at `~/.config/spacial-shell/config.toml`, decoded with
`dduan/TOMLDecoder` (`Package.swift` L13, resolved to 0.4.5 @ `a2bbd279` in `Package.resolved`).
The project's stated position is that the file *is* the interface —
`Sources/SpacialShell/AppRuntime.swift:103-105` comments that Fn+, "opens the config file the whole
app is actually driven by", and that "No settings UI exists (and none is pretended)". Users
hand-edit it, with comments.

We want a GUI settings window that edits the **same file**. The risk is obvious: clobbering the
user's comments and key ordering on every write. This note establishes what is actually possible in
Swift today, and what comparable projects actually do.

Two facts about the repo as it stands, because they bound every option below:

- [H] `Config` is already `Codable` in both directions (`Sources/SpacialShellKit/Config/Config.swift:56`);
  only a TOML *encoder* is missing. Load path is `Config.parse(toml:)` → `TOMLDecoder().decode` (L119-120).
- [H] **The repo already runs a two-file split.** `Paths.configFile` = `~/.config/spacial-shell/config.toml`
  (hand-edited, read-only to the app) and `Paths.stateFile` =
  `~/Library/Application Support/SpacialShell/state.json`, written by
  `PersistedState.save(to:)` from `AppRuntime.swift:248` and `:355`.
  `PersistedState` is a versioned `Codable` struct (`Sources/SpacialShellKit/State/PersistedState.swift:3-13`)
  holding per-screen workspace names, symbols, layouts, pinned flags and the Zen flag.

---

## 1. Maintained Swift TOML encoders / serializers

### 1a. The spec-level reason this is hard

- [H] TOML "is designed to map unambiguously to a hash table"
  ([toml.md L12](https://github.com/toml-lang/toml/blob/main/toml.md)). Comments are lexical only —
  "A hash symbol marks the rest of the line as a comment, except when inside a string"
  ([toml.md L49-61](https://github.com/toml-lang/toml/blob/main/toml.md)) — and have no home in the
  data model. Any library whose in-memory representation is the *data model* therefore cannot
  round-trip comments, key order or spacing, no matter how good it is. Format preservation requires
  a **concrete syntax tree**, which is a different kind of library.

### 1b. The libraries

| Library | Repo | Licence | Last meaningful commit | SwiftPM | macOS min | Serializes? |
|---|---|---|---|---|---|---|
| **TOMLDecoder** (ours) | [dduan/TOMLDecoder](https://github.com/dduan/TOMLDecoder) | MIT | 2026-07-11 `a2bbd279` "Bump version to 0.4.5" | yes | `.macOS(.v10_15)` | **no** |
| **TOMLKit** | [LebJe/TOMLKit](https://github.com/LebJe/TOMLKit) | MIT | 2025-01-18 `a6d92110` | yes | `.macOS(.v10_15)` | yes (lossy) |
| **swift-toml** | [mattt/swift-toml](https://github.com/mattt/swift-toml) | MIT | 2026-02-01 `827506c9` "Bump version to 2.0.0" | yes | `.macOS(.v10_15)` | yes (lossy) |
| **swift-toml-edit** | [akira-toriyama/swift-toml-edit](https://github.com/akira-toriyama/swift-toml-edit) | MIT | 2026-09-11 `5b7cb262` | yes | see 2c | yes (**format-preserving**) |
| jdfergason/swift-toml | [jdfergason/swift-toml](https://github.com/jdfergason/swift-toml) | Apache-2.0 | 2020-06-06 — **dormant 6 yrs** | yes | unverified | unverified |
| dduan/TOMLDeserializer | [archived](https://github.com/dduan/TOMLDeserializer) | MIT | archived; "Replaced by TOMLDecoder" | — | — | no |

There is no `JohnSundell/TOMLKit` — `gh api repos/JohnSundell/TOMLKit` → 404. The name belongs to
LebJe. (`kumabook/TOMLKit`, last touched 2017, is an abandoned namesake.)

**TOMLDecoder — decode-only, confirmed against its own source, not on assertion:**

- [H] The whole `Sources/TOMLDecoder/` tree is parser + decoder: `Parsing/{Parser,Token,TOMLDocument,Constants}.swift`,
  `TOMLDecoder.swift`, `_TOMLDecoder.swift`, `TOML{Keyed,Unkeyed,SingleValue}DecodingContainer`,
  `TOMLTable.swift`, `TOMLArray.swift`, `DateTime.swift`, `TOMLError.swift`, `TOMLKey.swift`.
  No encoder, no serializer, no writer file exists
  (`gh api repos/dduan/TOMLDecoder/git/trees/main?recursive=1`).
- [H] The one `encode(to:)` in the package is a deliberate trap:
  `TOMLTable.encode(to _: any Encoder) throws { throw TOMLError(.notReallyCodable) }`, doc-commented
  "This is not a full `Codable` conformance… Attempting to use it with other encoder or decoder will
  result in a `TOMLError` error" —
  [TOMLTable.swift L400-425](https://github.com/dduan/TOMLDecoder/blob/a2bbd279/Sources/TOMLDecoder/TOMLTable.swift).
- [H] Comments are discarded at lex time: `Parsing/Parser.swift:61` — `// skip comment, stop just before the \n.`
  ([Parser.swift](https://github.com/dduan/TOMLDecoder/blob/a2bbd279/Sources/TOMLDecoder/Parsing/Parser.swift)).
- [H] Only dependencies are opt-in, env-gated dev tools (benchmarks / docc / SwiftFormat); the shipped
  library target has none ([Package.swift](https://github.com/dduan/TOMLDecoder/blob/a2bbd279/Package.swift)).
  Actively maintained: three releases in the week to 2026-07-11.
  **So: adding write support means adding a second TOML dependency. There is no encoder to switch on.**

**TOMLKit (LebJe) — serializes, and drops every comment. Probed, not inferred:**

- [H] Encoder exists: `Sources/TOMLKit/Encoder/{TOMLEncoder,InternalTOMLEncoder,KeyedEncodingContainer,UnkeyedEncodingContainer,SingleValueEncodingContainer}.swift`.
  Wraps the C++ library toml++ via a `CTOML` target
  ([Package.swift](https://github.com/LebJe/TOMLKit/blob/a6d92110/Package.swift), tools-version 5.4).
- [H] **Probed** (`scratchpad/tkprobe`, TOMLKit 0.6.0 @ `ec6198d3`, resolved and built on this Mac):
  parse a 9-line config with four comments (a header block, a key comment, a trailing `# trailing comment`,
  a comment inside `[rail]`), set one value, `table.convert()` →

  ```
  gap = 12
  zen = false

  [rail]
  width = 64
  ```

  All four comments gone, silently. There is no option to keep them: `FormatOptions` exposes exactly
  quoting / indentation / integer-base flags —
  [FormatOptions.swift](https://github.com/LebJe/TOMLKit/blob/a6d92110/Sources/TOMLKit/FormatOptions.swift).
- [M] Maintenance is thin: last commit 2025-01-18, last release 0.6.0 on 2024-01-03
  (`gh api repos/LebJe/TOMLKit/releases`). It builds and runs clean under Swift 6.4 on macOS 14+ today (probed).
- [H] It is the TOML library AeroSpace and its fork use
  ([aerospork README L61](https://github.com/wbsmolen/aerospork/blob/main/README.md): "TOMLKit (config parsing)").

**mattt/swift-toml — same backend, same loss, better maintained:**

- [H] `Sources/TOML/{Decoder,Encoder,Value,LocalDateTime,Shared}.swift` over a C bridge to toml++
  (`Sources/CTomlPlusPlus/`); v2.0.0 dropped the C++-interop requirement
  ([README](https://github.com/mattt/swift-toml/blob/827506c9/README.md)).
  MIT, `.macOS(.v10_15)`, Swift 6.0 tools
  ([Package.swift](https://github.com/mattt/swift-toml/blob/827506c9/Package.swift)).
  README claims 100% on the toml-test compliance suite.
- [H] `TOMLEncoder().encode(config)` → `Data` is documented in the README. Round-trip fidelity is
  *value* fidelity only — the README's stated formatting knobs are "Sorted keys option for
  deterministic output", i.e. it re-serializes from the data model. Comment loss follows from toml++
  (see §2a), not probed directly for this package.

### 1c. Round-trip fidelity, stated honestly

- [H] For TOMLDecoder: not applicable — you cannot encode at all.
- [H] For TOMLKit and mattt/swift-toml: decoding then encoding produces a **semantically equal,
  textually different** document. Comments, blank lines, key order within a table, quoting style and
  integer base are all normalised away. For a file whose comments are the documentation, this is
  data loss on every save.
- [H] It is worse than cosmetic for us specifically: anything `Config` does not model is *deleted*,
  not merely reformatted. A user's future-version keys, a typo'd key they are mid-debug on, and any
  section a newer build understands but this one doesn't all vanish on the first GUI save.

---

## 2. Comment-preserving / format-preserving TOML editing in Swift

### 2a. toml++ (and therefore both toml++-backed Swift packages) does **not** preserve comments

- [H] [marzer/tomlplusplus#28 "Preservation of comments and whitespace"](https://github.com/marzer/tomlplusplus/issues/28)
  — opened 2020-05-20, **still open** as of 2026-09-12. The requester's use case is exactly ours:
  "We currently have TOML config files where the original source is commented with documentation
  describing each option, but once it passes through tomlplusplus all those comments get lost."
- [H] The maintainer's position, same thread: "It's tentatively on my mental road-map for `toml++`
  though might be a decent while before I can make time to implement it" (2020-05-20), and later
  that comments would be metadata on nodes, opt-in, "here be dragons".
- [H] A community implementation exists and was **not merged**:
  [PR #283 "Trivia preservation"](https://github.com/marzer/tomlplusplus/pull/283) — opened
  2025-09-18, closed unmerged by `marzer` on 2026-03-23. Maintainer feedback was storage overhead
  ("make this entire feature opt-in at compile-time… otherwise the overheads are likely to be
  unacceptable") and a stale base branch. The author's own TODO list still had "preserve numeric
  literal encoding" and "preserve string encoding" unchecked.
- [H] Consequence: **LebJe/TOMLKit preserves nothing, and cannot, without an upstream change.**
  Same for mattt/swift-toml. Confirmed by the TOMLKit probe in §1b.

### 2b. The plain answer

- [H] **No mature Swift library does comment-preserving TOML editing.** There is no Swift equivalent
  of [`toml_edit`](https://crates.io/crates/toml_edit) (Rust; 0.25.15, 808M downloads, "Yet another
  format-preserving TOML parser") or [`tomlkit`](https://pypi.org/pypi/tomlkit/json) (Python; 0.15.1,
  "Style preserving TOML library") with any comparable track record. GitHub repo search across
  `toml+language:swift`, `toml+edit+language:swift`, `lossless+toml+language:swift` and
  `toml+comment+preserving+language:swift` returns exactly one candidate, below.
  **That is a clear negative, and it is the central finding of this note.**

### 2c. The one candidate: `akira-toriyama/swift-toml-edit` — real, works, unproven

Reported with full caveats because it is the only thing in the category.

- [H] MIT, created 2026-06-15, last push 2026-09-11, tagged through **v3.0.0**, zero dependencies,
  pure Swift + Foundation, `Sendable` value-type DOM. Sources:
  `Sources/Toml/{Annotated,AnnotatedEdit,AnnotatedParse,ParseWithSpans,Lexer,Serialize,DecodeStrict}.swift`.
  [README](https://github.com/akira-toriyama/swift-toml-edit/blob/main/README.md) states it passes
  the official `toml-test` v2.2.0 suite pinned to TOML 1.0.0 in both directions (decoder 205/205 valid,
  474/474 invalid rejected; encoder 205/205), with a byte-identity corpus and a generative fuzzer.
- [H] **Probed** (`scratchpad/teprobe`, v3.0.0 @ `603c4028`, resolved and built on this Mac). Same
  9-line commented fixture as the TOMLKit probe:
  - `Toml.Annotated(parsing: src).render() == src` → **`true`**. Byte-identical untouched round-trip.
  - `doc.settingValue(.int(12), atTable: ["rail"], forKey: "width").render()` → every comment, the
    blank line, and the `gap = 8            # trailing comment` column alignment survive verbatim;
    only `width = 64` becomes `width = 12`. This is genuinely `toml_edit`-shaped behaviour in Swift.
  - **Gotcha found in the same probe:** `settingValue(.int(12), atTable: [], forKey: "gap")` —
    a *root-level* key, no `[header]` — **silently no-ops**. It returns an unchanged document with no
    error. The doc comment says the op targets "the FIRST `[path]` std table"
    ([AnnotatedEdit.swift L184](https://github.com/akira-toriyama/swift-toml-edit/blob/v3.0.0/Sources/Toml/AnnotatedEdit.swift)),
    and SpacialShell's config has root-level scalars. A silent no-op on save is a worse failure mode
    than a throw.
- [M] Maturity risk is the whole story: **1 star, 0 forks, one human contributor** (52 commits;
  the only other contributor is dependabot), GitHub code search finds 2 `Package.swift` references
  (its own sibling projects). The README says it is "the shared TOML library for the atelier swift
  app family" — i.e. one author's own toolchain. It carries a `CLAUDE.md` design doc, so it is at
  least partly agent-authored. Its API has churned through three majors in three months (v2.0 typed
  spans, v2.1 value edit ops, v2.3 `parseWithSpans`, v3.0 retired the line-based scanner).
- Verdict to hand the humans: **technically it does the thing; as a dependency it is a bet on one
  stranger's side project.** Vendoring it (MIT) converts the supply-chain risk into a maintenance
  cost we own. Platform floor is unverified against `.macOS(.v14)` beyond "it built and ran here".

### 2d. The other way people get format preservation: don't parse, do line surgery

Covered in §3 (aerospork) — it is the only shipped precedent on macOS/Swift, and its source is
frank about what it costs.

---

## 3. What comparable tools actually do

### 3a. AeroSpace — our closest peer — never writes the config, and says so

- [H] The config file is read-only to the app. `Sources/AppBundle/config/ConfigFile.swift` is 33 lines
  containing only `findCustomConfigUrl()`; the rest of `config/` is `parse*.swift` readers plus a watcher.
  A repo-wide grep for `write(to`/`createFile` over `Sources/` returns exactly one write — a temp file
  for an error dialog ([showMessageInGui.swift L12](https://github.com/nikitabobko/AeroSpace/blob/39e5190/Sources/Common/util/showMessageInGui.swift#L12)).
- [H] `aerospace config` is read-only by construction — modes are `--get <key>`, `--major-keys`,
  `--all-keys`, `--config-path`, with no setter
  ([ConfigCommand.swift L6-28](https://github.com/nikitabobko/AeroSpace/blob/39e5190/Sources/AppBundle/command/impl/ConfigCommand.swift#L6-L28)).
- [H] The GUI is a tray menu whose config items are "open in editor" and "reload"
  ([MenuBar.swift L61-62, L91-120](https://github.com/nikitabobko/AeroSpace/blob/39e5190/Sources/AppBundle/ui/MenuBar.swift#L61-L120)).
- [H] Stated position, README design principles: "AeroSpace doesn't use GUI, unless necessarily —
  **AeroSpace will never provide a GUI for configuration.** For advanced users, it's easier to edit a
  configuration file in text editor rather than navigating through checkboxes in GUI."
  ([README.md L118-120](https://github.com/nikitabobko/AeroSpace/blob/39e5190/README.md#L118-L120))
- [H] Its one GUI-set value goes to **UserDefaults**, not the TOML: the "Experimental UI Settings"
  submenu writes `displayStyle` via `UserDefaults.standard.setValue(_:forKey:)`
  ([ExperimentalUISettings.swift L1-16, L40-68](https://github.com/nikitabobko/AeroSpace/blob/39e5190/Sources/AppBundle/ui/ExperimentalUISettings.swift)).
  That is the two-file split in miniature, in the project we already borrow from.
- [H] Direction of authority is config → OS, never back: `start-at-login` in the TOML drives
  `SMAppService.register()/unregister()`
  ([startAtLogin.swift L5-14](https://github.com/nikitabobko/AeroSpace/blob/39e5190/Sources/AppBundle/config/startAtLogin.swift#L5-L14)).

### 3b. aerospork — an AeroSpace fork that *did* build the GUI, and wrote down what it cost

The single most relevant artifact found. [wbsmolen/aerospork](https://github.com/wbsmolen/aerospork)
(MIT, created 2025-07-08, macOS 13+, TOMLKit + Sparkle only) is a fork whose pitch is literally
"TOML config, and a settings GUI" — 7 native panes against upstream's refusal
([README L15, L58-66, L130-136](https://github.com/wbsmolen/aerospork/blob/main/README.md)).

- [H] **It rejected re-serialization outright.** README L108-113: "**The config writer is line-based
  on purpose.** Re-serializing the whole file would be far simpler, and would destroy every comment
  plus anything the GUI cannot model, such as per-monitor gap arrays. Instead it rewrites only the
  keys you changed, preserves what the panes cannot model … field for field on every save, and
  refuses the few shapes it cannot rewrite safely, pointing you at the Raw TOML pane. That is what
  makes a GUI safe to put on top of a dotfile."
- [H] The implementation is
  [`Sources/AppBundle/config/ConfigurationWriter.swift`](https://github.com/wbsmolen/aerospork/blob/main/Sources/AppBundle/config/ConfigurationWriter.swift)
  — **883 lines** for what a `TOMLEncoder().encode()` would do in one. Its governing rule, in the
  `render` doc comment: "a section the user did not edit is left exactly as it was, byte for byte.
  This is not an optimization — the view model models a lossy projection of the config … so
  unconditionally re-serializing a section *destroys* anything the UI can't express."
- [H] **Nine legal TOML spellings defeat line surgery**, so the writer detects and *refuses* them
  rather than corrupting the file — `unsupportedShapeReason(_:)` (L216-268+). Named cases include:
  CRLF or classic-Mac line endings (Swift treats `\r\n` as one `Character`, so `split(separator: "\n")`
  never splits the file and the writer appended duplicate `[gaps]` tables); a sub-table of a
  wholesale-rewritten section; a multi-line array spelling of a managed scalar or a binding; a
  *quoted* key where the writer expects a bare one ("would duplicate rather than replace"); a dotted
  or inline spelling of a managed section (`gaps.inner.horizontal = 5`,
  `exec = { inherit-env-vars = false }`). The comments record that these were found by a property
  fuzzer (`Sources/AppBundleTests/config/ConfigSafetyWriterFuzzTest.swift`) after damaging a real config.
- [H] Supporting machinery the same file carries, all of which a real implementation needs:
  a hand-rolled quote-aware `bracketBalance(_:)` (L245-266) because it is "Deliberately not a TOML
  parser"; timestamped rolling backups, 5 generations, because "A single `.backup` was worse than
  useless: the save that made the user notice the damage was also the save that overwrote the last
  good copy" (L74-107); `ConfigFileWatcher.suppressNextSelfWrite()` so the app's own save doesn't
  trigger its hot-reload; pre-write validation via `parseConfig` *and* `TOMLTable(string:)` for
  line/column diagnostics, because "A config that fails to parse used to land on disk anyway"
  (L188-214); trailing-newline and blank-line preservation, after a bug where four saves of the same
  edit stacked "5, 6, 7, 8 lines" of blank drift into the user's dotfile; and an escape-hatch **Raw
  TOML pane** that bypasses the whole mechanism.
- [M] Fork context: the author states upstream closed his monitor PR without review, so the fork is
  not evidence that upstream reconsidered its position ([README L33-37](https://github.com/wbsmolen/aerospork/blob/main/README.md)).

### 3c. Terminals and editors

- [H] **Alacritty** — strictly one-way. The only config write in the tree is the explicit
  `alacritty migrate` CLI subcommand, which does a silent dry run first and then an atomic
  temp-file-and-persist
  ([migrate/mod.rs L33-45, L228-246](https://github.com/alacritty/alacritty/blob/d692748/alacritty/src/migrate/mod.rs)).
  The loader only reads ([config/mod.rs L210-236](https://github.com/alacritty/alacritty/blob/d692748/alacritty/src/config/mod.rs)).
  Runtime overrides via `alacritty msg config` are memory-only and `--reset`-able
  ([event.rs L294-320](https://github.com/alacritty/alacritty/blob/d692748/alacritty/src/event.rs);
  [alacritty-msg.1.scd L56-79](https://github.com/alacritty/alacritty/blob/d692748/extra/man/alacritty-msg.1.scd)).
  README FAQ refuses the surface outright: "you won't find things like tabs or splits … nor niceties
  like a **GUI config editor**" ([README L99-106](https://github.com/alacritty/alacritty/blob/d692748/README.md)).
  No app-owned state file at all.
- [H] **Ghostty** — the most directly useful precedent, because its maintainer has written down the
  design for exactly our problem. No GUI settings pane exists; ⌘, runs `openConfig:` which hands the
  file to `$EDITOR`
  ([MainMenu.xib L97-99](https://github.com/ghostty-org/ghostty/blob/e2e53f8/macos/Sources/App/MainMenu.xib#L97-L99),
  [Ghostty.App.swift L130-141](https://github.com/ghostty-org/ghostty/blob/e2e53f8/macos/Sources/Ghostty/Ghostty.App.swift#L130-L141)),
  and the in-tree stub window says "Coming Soon. 🚧 / You can't configure settings in the GUI yet"
  ([SettingsView.swift L3-25](https://github.com/ghostty-org/ghostty/blob/e2e53f8/macos/Sources/Features/Settings/SettingsView.swift#L3-L25)).
  The only write is a **comment-only template** created when no config exists
  ([Config.zig L4145-4160](https://github.com/ghostty-org/ghostty/blob/e2e53f8/src/config/Config.zig#L4145-L4160),
  [config-template](https://github.com/ghostty-org/ghostty/blob/e2e53f8/src/config/config-template)) —
  note SpacialShell's `AppRuntime.swift:109-112` already does the same thing, only with an empty file.
  mitchellh, [discussion #2354](https://github.com/ghostty-org/ghostty/discussions/2354#discussioncomment-10823397):

  > "I think a graphical preference window is desirable… But that doesn't mean doing away with the
  > text-based config, either! … The way we do parsing of the text file right now it'd be a pain to
  > preserve whitespace and comments in order to rewrite it. I think we should instead go with a
  > **priority approach**, something like: GUI takes priority over the XDG file at
  > `~/.config/ghostty/config`. **This way, we never overwrite a user's text config.** We store the
  > GUI config in NSUserDefaults (or something) … We'd only write values that differ from defaults."

- [H] **Helix** — never writes config. `:set` / `:toggle` patch the in-memory config and send
  `ConfigEvent::Update` over a channel, with no filesystem call
  ([typed.rs L2279-2400](https://github.com/helix-editor/helix/blob/079a789/helix-term/src/commands/typed.rs#L2279-L2400));
  the generated docs say "Set a config option **at runtime**"
  ([typable-cmd.md L75-76](https://github.com/helix-editor/helix/blob/079a789/book/src/generated/typable-cmd.md#L75-L76)).
  `:config-open` opens the file as an ordinary buffer — the user types `:w`.
  App-owned state goes to a separate store: workspace trust at
  `data_dir()/workspace_trust/<sha256(path)>`, one small `key = value` file per workspace
  ([workspace_trust.rs L1-27, L405-412, L481-500](https://github.com/helix-editor/helix/blob/079a789/helix-loader/src/workspace_trust.rs)).
  Note the layering: the human-editable `[editor.workspace-trust] trusted = [...]` escape hatch lives
  in `config.toml` and is documented as discouraged, while app-granted trust lives in the state store.
- [H] **Rio** — no write-back found. `create_config_file(path)` returns immediately if the file exists
  and otherwise writes the default template; that is the only config write
  ([rio-backend/src/config/mod.rs L239-249](https://github.com/raphamorim/rio/blob/main/rio-backend/src/config/mod.rs)).
  Font-size changes are in-memory only (`screen/mod.rs L1322-1330`). A whole-document
  `Config::to_string()` using plain `toml` exists at L375-377 but has **no located call site**
  (unverified — code search can miss). There is no settings route in
  `frontends/rioterm/src/router/routes/`.
- [H] **Starship** — the counter-example, and the cleanest small reference implementation.
  `starship config <name> <value>` and `starship toggle <name> <key>` *do* rewrite `starship.toml`
  ([main.rs L263-279](https://github.com/starship/starship/blob/master/src/main.rs)), via
  **`toml_edit::DocumentMut`** — a format-preserving CST, listed in `Cargo.toml` *alongside* plain
  `toml` precisely because the two jobs are different. The decisive detail is that it explicitly
  copies the old node's trivia onto the new one:
  `*new_value.as_value_mut().unwrap().decor_mut() = value.decor().clone();`
  ([configure.rs L66-69, also L219](https://github.com/starship/starship/blob/master/src/configure.rs)),
  then writes the whole document atomically. Caveat in the same file: a syntactically broken config
  hits `.expect("Failed to load starship config")` and panics rather than being clobbered (L231-239).
  `starship preset` is *not* an edit — it writes a preset file and expects the user to append it
  themselves ([print.rs L530-546](https://github.com/starship/starship/blob/master/src/print.rs)).
- [H] **Zed** — a GUI settings surface over a hand-edited JSONC file, done surgically.
  `update_settings_file` ([settings_file.rs L269-275](https://github.com/zed-industries/zed/blob/main/crates/settings/src/settings_file.rs))
  is called by every GUI surface; `edits_for_update_inner`
  ([settings_store.rs L893-925](https://github.com/zed-industries/zed/blob/main/crates/settings/src/settings_store.rs))
  diffs the typed struct old-vs-new and calls `update_value_in_json_text`, whose own comment states
  the rule: "If the old and new values are both objects, then compare them key by key, **preserving
  the comments and formatting of the unchanged parts.** Otherwise, replace the old value with the new
  value." The surgery is **tree-sitter**: a `(pair key: (string) @key value: (_) @value)` query
  locates the node and `replace_value_in_json_text` returns a `(Range<usize>, String)` byte-range
  replacement
  ([settings_json.rs L15, L76-95](https://github.com/zed-industries/zed/blob/main/crates/settings_json/src/settings_json.rs));
  indentation is sniffed from the existing file. Writes are `fs.atomic_write`. Comments inside a
  value node that is replaced wholesale are still lost.
- [H] **VS Code** — same shape, different parser. The Settings UI writes `settings.json` via
  `ConfigurationEditing` → `setProperty` from `base/common/jsonEdit.ts`, which parses to an AST and
  emits a minimal `{offset, length, content}` edit
  ([configurationEditing.ts L244-262](https://github.com/microsoft/vscode/blob/main/src/vs/workbench/services/configuration/common/configurationEditing.ts),
  [jsonEdit.ts](https://github.com/microsoft/vscode/blob/main/src/vs/base/common/jsonEdit.ts)).
  Whole-file `JSON.stringify` is reached **only** when no key path is given, and the code says so
  in a comment at L249-250.

---

## 4. Is the two-file split the common answer?

[H] **Yes — with one precise qualification.** Among the projects examined, every one that keeps a
hand-edited config *and* has app-set values keeps them in a different store. But the two stores hold
**disjoint concerns** (user preferences vs. session/window/app state); only Ghostty proposes an
actual *precedence chain* where a GUI store shadows the same keys the config file sets, and that
GUI does not exist yet.

For the split:

- [H] **Ghostty** — the stated plan, verbatim: GUI values in NSUserDefaults taking priority over the
  XDG text config, "This way, we never overwrite a user's text config", writing only values that
  differ from defaults. And the reason given is exactly ours — preserving whitespace and comments
  "would be a pain" ([discussion #2354](https://github.com/ghostty-org/ghostty/discussions/2354#discussioncomment-10823397)).
  This is the only found instance of a maintainer choosing layering *because of* the comment problem.
- [H] **AeroSpace** — TOML read-only; the one GUI toggle in `UserDefaults`
  ([ExperimentalUISettings.swift](https://github.com/nikitabobko/AeroSpace/blob/39e5190/Sources/AppBundle/ui/ExperimentalUISettings.swift)).
- [H] **Zed** — `settings.json` (user-owned) vs `~/.local/share/zed/db/` SQLite for window state, pane
  tree, recent/remote projects
  ([db.rs](https://github.com/zed-industries/zed/blob/main/crates/db/src/db.rs),
  [persistence.rs L540-1078](https://github.com/zed-industries/zed/blob/main/crates/workspace/src/persistence.rs)),
  plus a generic `kv_store` / `scoped_kv_store` with a `Dismissable` trait so "user dismissed this
  banner" never touches settings.json
  ([kvp.rs](https://github.com/zed-industries/zed/blob/main/crates/db/src/kvp.rs)).
  Documented precedence for the *settings* layers is Default → User → Project, later wins, objects
  merge rather than replace (`docs/src/configuring-zed.md`, §How Settings Merge). The SQLite store is
  not in that chain.
- [H] **VS Code** — `settings.json` vs `state.vscdb` SQLite for window/editor layout and extension state
  ([storageMain.ts](https://github.com/microsoft/vscode/blob/main/src/vs/platform/storage/electron-main/storageMain.ts),
  [storageService.ts](https://github.com/microsoft/vscode/blob/main/src/vs/platform/storage/common/storageService.ts)).
- [H] **Neovim** — `init.lua` never written by nvim; mutable state under `$XDG_STATE_HOME`
  (shada, trust DB) ([stdpaths.c](https://github.com/neovim/neovim/blob/master/src/nvim/os/stdpaths.c)).
- [H] **Helix** — `config.toml` never written; workspace trust in `data_dir()` (§3c).
- [H] **SpacialShell already does this** — `config.toml` read-only, `state.json` in Application Support
  (see §0 facts). The split is not a new architecture here; it is the one already in the repo.

Against the split / for writing the file:

- [H] **Starship** writes the user's TOML from a CLI — with `toml_edit` and explicit decor copying (§3c).
- [H] **VS Code and Zed** write the user's config from a GUI — both with AST/CST byte-range surgery,
  never re-serialization (§3c).
- [H] **aerospork** writes the user's TOML from a GUI — with 883 lines of line surgery, a nine-case
  refusal list, a fuzzer, rolling backups and a raw-text escape hatch (§3b).
- [H] **Cargo** (`cargo add`/`remove`) and **Poetry** (`poetry add`) mutate user manifests through
  `toml_edit` and `tomlkit` respectively
  ([cargo Cargo.toml](https://github.com/rust-lang/cargo/blob/master/Cargo.toml),
  [poetry add.py L128-131, L320-413](https://github.com/python-poetry/poetry/blob/main/src/poetry/console/commands/add.py)).

**The pattern, distilled: nobody who writes a user's commented config file re-serializes it from a
data model. Every shipped example either (a) doesn't write the file, or (b) locates a key path in a
lossless CST / line buffer and replaces exactly that span. There is no third approach in the wild.**

---

## What this means for SpacialShell

The binding constraint: **Swift has no mature format-preserving TOML library** (§2b), and our current
dependency cannot write TOML at all (§1b). Every option below is a way of paying for that.

The options, with their real costs. No recommendation is made here.

**Option A — GUI writes nothing; it is a viewer plus "Open config" (status quo, formalised).**
- Cost: zero. `AppRuntime.swift:103` already does this; a settings *window* could show the parsed
  config read-only, with validation errors and the cheat sheet, and an "Edit in…" button.
- Precedent: AeroSpace (explicitly), Alacritty (explicitly), Helix, Ghostty today.
- What it fails to deliver: the actual ask. Checkboxes that don't set anything are a worse surface
  than the file.

**Option B — two-file split: GUI writes an app-owned store that layers over the TOML.**
- Shape: extend `PersistedState` (or add a sibling `settings.json` / `UserDefaults` domain) with GUI
  overrides; resolution order becomes defaults → `config.toml` → GUI store, last wins.
- Cost: the config file is no longer the single source of truth, which is a direct contradiction of
  the position in `AppRuntime.swift:103`. Two places to look when a setting is "wrong". Needs a
  visible affordance in the GUI for "this is overriding your config file, reset to file", or users
  will edit the TOML and see nothing change — the most likely support burden.
- Cost: near-zero *engineering* cost. The store, its versioning, its atomic save path and its
  Application Support directory all exist today (`PersistedState`, `AppRuntime.swift:248`).
- Precedent: strongest and broadest (§4). Ghostty picked it for exactly our reason. It is also the
  only option that is already half-built in this repo.

**Option C — write `config.toml` with surgical line editing (the aerospork road).**
- Cost, measured on the one project that shipped it: ~880 lines of writer, a nine-entry refusal list
  for legal TOML spellings it cannot handle, a property fuzzer that found most of those cases after
  they damaged a real config, rolling timestamped backups, self-write suppression in the file
  watcher, pre-write validation, and a raw-text escape hatch pane for everything refused.
  See §3b for citations on each.
- Benefit: the config file stays the single source of truth. The user's comments survive. GUI and
  editor stay in agreement.
- Risk: the failure mode of a bug here is silent deletion of a user's config data, which is the worst
  class of bug this project could ship. aerospork's own comments document that it shipped that bug
  twice before the fuzzer existed.

**Option D — adopt `swift-toml-edit` and do Option C's job with a real CST.**
- Cost: a second TOML dependency (we'd be parsing with TOMLDecoder and editing with `Toml`), on a
  package with 1 star, one human author, three majors in three months, and a probed silent-no-op on
  root-level keys — which our config has (§2c). MIT, so vendoring is available and converts supply
  chain risk into maintenance we own.
- Benefit: probed byte-identical round-trip and correct surgical edit on this Mac today. It is
  `toml_edit`'s behaviour, which is the mechanism Starship, Cargo and Poetry all rely on.
- Open work before this is viable: verify `.macOS(.v14)` floor; decide vendor-vs-depend; write our own
  round-trip test over the repo's real `config.toml` fixtures; handle or patch the root-key no-op;
  decide what happens to keys the GUI cannot model (`toml_edit` preserves them for free — that is the
  point — but our `Config` → document mapping still has to be written per-key, not bulk-encoded).

**Option E — encode with TOMLKit / mattt/swift-toml.**
- Cost: **destroys every comment on every save** (probed, §1b), plus every key `Config` doesn't model.
- Listed only so it is on the record as considered and rejected on evidence. No examined project does
  this to a user's config file.

Cross-cutting, whichever is chosen:

- [H] Any write path needs self-write suppression in the config watcher or the save triggers a reload
  storm (aerospork `ConfigFileWatcher.suppressNextSelfWrite()`, §3b).
- [H] Validate *the exact bytes about to be written*, before writing, not after — aerospork's comment
  records shipping the other order and leaving users with a broken file plus two error dialogs.
- [H] Atomic write is table stakes: Zed `fs.atomic_write`, Starship `write_file_atomic`, Alacritty
  temp-then-persist, aerospork `write(to:atomically:true)`.
- [M] A "Raw TOML" pane (aerospork) or an "Open in editor" button (Ghostty, AeroSpace, Helix) is the
  standard escape hatch for anything the structured UI refuses or cannot model. It is cheap and it is
  what makes a refusal acceptable to a user.

Unverified / left open: whether Rio's `Config::to_string()` has a caller outside tests; whether
`swift-toml-edit` builds against our exact `.macOS(.v14)` floor in CI (it built and ran here);
comment-loss in `mattt/swift-toml` was inferred from its toml++ backend rather than probed directly.
