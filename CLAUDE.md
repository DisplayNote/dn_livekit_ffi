# CLAUDE.md

@AGENTS.md

`AGENTS.md` is the source of truth (including the `## Security` section). This file
only adds Claude Code-specific DO / DON'T rules.

## DO

- Keep changes inside the DisplayNote fork delta listed in `AGENTS.md` unless the task is an upstream sync.
- When adding a C entry point, update both `livekit-ffi/src/cabi.rs` and `livekit-ffi/include/livekit_ffi.h`.
- Patch libwebrtc through `webrtc-sys/libwebrtc/patches/` and the `patches=(…)` list in `build_android.sh`.
- Run `cargo fmt -- --check` before committing Rust changes.
- Use `/log-sanitise <file…>` before looking at any LiveKit / host log (see `docs/runbooks/debugging-with-ai.md`).
- Know the Azure stage order: `setup` and the two scan gates (`SecretScan`, `DependencyScan`, in parallel) → WebRTC builds (each `dependsOn: [SecretScan, DependencyScan]`) → FFI builds → deploy (which also lists both gates). A new WebRTC build stage must pass the same `dependsOn`.
- Treat both scan gates as blocking. `.gitleaksignore` fingerprints each need a preceding comment line (never a trailing one); `osv-scanner.toml` exceptions each need a `reason` and an `ignoreUntil` ≤ 180 days. After an upstream sync, triage new findings rather than widening either file.
- Treat `.agents/skills/*` and `.github/skills/*` as generated: re-sync with `/sync-skill <name>` from the `displaynote-engineering` plugin instead of hand-editing.

## DON'T

- Don't run `build_android.sh` / `generate_conan_build.sh` casually: they clone depot_tools, sync WebRTC (many GB), `git reset --hard` the WebRTC checkout and `cargo clean`.
- Don't fetch, push or rebase against the `upstream` remote unless the task is the upstream sync described in `FORK_DOCUMENTATION.md`.
- Don't log tokens, URLs with query strings, `JoinResponse`/`ReconnectResponse`, SDP, ICE candidates, request/event `{:?}` dumps or participant identities at any level.
- Don't remove `JniInit`/`JniUtil` from the keep list in `strip_jni_zero.sh`.
- Don't edit generated files (`livekit-ffi/src/livekit.proto.rs`, `livekit-protocol/src/livekit.rs`) by hand.
- Don't point `resources.repositories` in `.azure/pipelines/` at a PAT-based service connection; use `endpoint: "DisplayNote"` (GitHub App).
