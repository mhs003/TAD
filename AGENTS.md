# AGENTS.md

Guidance for coding agents working in the **TAD** repository.

## What this is

TAD is a shell-only CLI (`tad`) that builds, installs and tests Kotlin +
Jetpack Compose Android apps entirely on an Android phone inside Termux. It has
no compiled component: it is Bash scripts plus a project template. Read
[ARCHITECTURE.md](ARCHITECTURE.md) before making non-trivial changes.

## Setup

```bash
./bin/tad-setup     # idempotent: Termux packages + Google Android SDK
tad doctor          # must report "all checks passed" before anything else
```

`tad-setup` is the only stage that downloads anything. Everything else is local
and cheap to re-run.

## Commands you will actually use

| Task | Command |
|---|---|
| Verify the toolchain | `tad doctor` |
| Scaffold a project | `tad new MyApp --package com.example.myapp` |
| Build and verify an APK | `tad build [debug\|release]` (from a project root) |
| Install and launch | `tad run` |
| Tests | `tad test unit` / `tad test instrumented` |
| Syntax-check every script | `for f in lib/common.sh bin/* install.sh; do bash -n "$f"; done` |

Run the syntax check after touching any script. There is no other lint, and no
test suite for the scripts themselves. To exercise the tool end to end, scaffold
a throwaway project in `$TMPDIR` and run `tad build` in it.

## Rules

- **Bash only.** Every script starts with
  `#!/data/data/com.termux/files/usr/bin/bash` and `set -euo pipefail`. Shared
  behaviour belongs in `lib/common.sh`; do not duplicate it.
- **`TAD_ROOT` is derived from the script's own path, never inherited.** Reading
  it from the environment breaks relocated installs.
- **Never put the SDK's `platform-tools` or `build-tools` on `PATH`.** Their
  x86-64 binaries shadow Termux's working ones and fail with
  `Exec format error`.
- **`KOTLIN_VERSION` in `tad.conf` must equal the Kotlin Gradle plugin AGP
  bundles** (AGP 9.4.1 → 2.2.10). The Compose compiler plugin uses that version,
  so the two must not drift.
- **Generated projects must not apply `org.jetbrains.kotlin.android`.** AGP 9
  compiles Kotlin itself; adding the plugin fails the build.
- **Do not trust `BUILD SUCCESSFUL`.** `tad build` verifies the APK contains a
  manifest, `resources.arsc` and dex, and checks the signature. Keep that check
  whenever you touch build code.
- **Add no new dependencies.** Termux packages and Google's official SDK only —
  no third-party repositories, prebuilt binaries, vendored scripts or
  `curl | bash` installers.
- **Change versions in `tad.conf`, not scattered across scripts.** It is the
  single source of version truth; `SDK_PLATFORM` is derived in `load_conf`.

## Output style

Scripts print through the helpers in `lib/common.sh` — `step`, `ok`, `warn`,
`err`, `kv`, `title`, `group`, `cmdrow`, `hr` — so formatting and colour stay
consistent. Colour is disabled when output is not a TTY or `NO_COLOR` is set;
`FORCE_COLOR=1` forces it on for tests.

## Commits

Short, meaningful subject lines. No co-author or tool-attribution trailers.
Commit and push at each coherent point rather than batching unrelated changes.

## Layout

```
bin/tad          dispatcher: `tad <cmd>` execs bin/tad-<cmd>
bin/tad-*        one script per subcommand
lib/common.sh    path resolution, output helpers, config/env, gradle + adb glue
tad.conf         versions and paths — the single source of truth
templates/       Compose project template (tokens rendered by tad-new)
install.sh       clone-or-pull, then run tad-setup
.agents/skills/  Agent Skill so agents can drive `tad`
```
