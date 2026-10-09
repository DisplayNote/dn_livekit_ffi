# AGENTS.md — dn_livekit_ffi

## Project snapshot

DisplayNote fork of [`livekit/rust-sdks`](https://github.com/livekit/rust-sdks)
(remote `upstream`), forked at `livekit-ffi@0.12.34` (upstream commit `02150915`).
It builds the `livekit-ffi` C ABI library (`liblivekit_ffi.so` + `libwebrtc.jar` for
Android, `livekit_ffi.dll` for Windows) and ships it as the Conan package
`livekit-ffi/<version>@dn/…`; dnbroadcast-qt consumes it for LiveKit streaming.
Stack: Rust 2021 workspace (stable toolchain), C++20 glue in `webrtc-sys` (cxx), a
custom libwebrtc build (GN/ninja via depot_tools), x264 (`webrtc-sys/third_party/x264`), Conan 1.x
recipe, Azure Pipelines.

Most of the tree is unmodified upstream code. DisplayNote's changes (≈50 files, see
`git diff 02150915 main --stat`) are listed in [Fork delta](#fork-delta); keep work
focused there.

## Security

- NEVER suggest hardcoded credentials, API keys, or connection strings
- NEVER generate code that logs PII or sensitive data
- Flag any code that introduces new external dependencies
- Prefer established authentication patterns (OAuth2, JWT) over custom implementations
- Do not generate SQL without parameterised queries
- Flag any configuration changes that affect network exposure or access controls
- NEVER read raw log files or paste log content into a prompt — sanitise with `dn_logscrub` first (`/log-sanitise <file>`) and work only from the `.scrubbed` copy (AI Security Roadmap 4.7)

Repo-specific: LiveKit access tokens (JWTs), TURN credentials from the `JoinResponse`
and room/participant identities flow through this library. Never add log lines that
print them; see [docs/runbooks/debugging-with-ai.md](docs/runbooks/debugging-with-ai.md)
for what the existing logging already exposes.

## Repository map

```text
livekit-ffi/          C ABI + protobuf FFI server (the shipped library) — DN: cabi.rs setter, cbindgen.toml,
                      include/livekit_ffi.h, conan_assets/, generate_conan_build.{sh,bat}
livekit/              Rust client SDK (Room, RtcEngine) — DN: set_force_sw_h264 in lib.rs + rtc_engine/lk_runtime.rs
livekit-api/          Signal client (WebSocket) + server APIs — upstream only
livekit-protocol/     Generated LiveKit protocol types — upstream only
libwebrtc/            Safe Rust wrapper over webrtc-sys — DN: PeerConnectionFactory::new(force_sw_h264)
webrtc-sys/           cxx bridge to libwebrtc — DN: build.rs (x264, Android factories), src/android/, src/x264/
webrtc-sys/libwebrtc/ libwebrtc build scripts + patches — DN: build_android.sh, migrate_webrtc.sh,
                      webrtc_structure.sh, strip_jni_zero.sh, patches/sw_h264_fallback.patch
webrtc-sys/build/     build-dependency crate that locates/downloads libwebrtc (LK_CUSTOM_WEBRTC)
.azure/pipelines/     DN release pipeline (tag-triggered): libwebrtc → livekit-ffi → Conan package
.github/workflows/    Upstream GitHub Actions (kept from upstream)
imgproc/ yuv-sys/ soxr-sys/ livekit-runtime/   upstream helper crates
examples/             upstream Rust examples (separate Cargo workspace)
```

## Fork delta

| Area | What DisplayNote changed | Files |
|---|---|---|
| Android package rename | WebRTC Java/JNI moved from `org.webrtc` to `livekit.org.webrtc` so the host app can ship its own WebRTC | `webrtc-sys/libwebrtc/migrate_webrtc.sh`, `webrtc_structure.sh`, `build_android.sh` |
| jni_zero de-duplication | `org.jni_zero` stripped from `libwebrtc.jar` except `JniInit`/`JniUtil` (AB#141676) | `webrtc-sys/libwebrtc/strip_jni_zero.sh` |
| App-controlled SW H264 | `livekit_ffi_set_force_sw_h264(bool)` → `livekit::set_force_sw_h264` → `PeerConnectionFactory::new(bool)` → `AndroidVideoEncoderFactory` (AB#135683) | `livekit-ffi/src/cabi.rs`, `livekit/src/lib.rs`, `livekit/src/rtc_engine/lk_runtime.rs`, `libwebrtc/src/*peer_connection_factory.rs`, `webrtc-sys/src/peer_connection_factory.{rs,cpp}`, `webrtc-sys/src/android/video_encoder_factory.cpp`, `webrtc-sys/libwebrtc/patches/sw_h264_fallback.patch` |
| x264 SW encoder | `use_x264` feature, x264 checkout in `webrtc-sys/third_party/x264` built by `build.rs`, used on Android when no HW encoder | `webrtc-sys/build.rs`, `webrtc-sys/src/x264/`, `webrtc-sys/include/livekit/x264/`, `.gitmodules` |
| Android C++ runtime | `c++_shared` instead of `c++_static` ("for Qt compatibility") | `webrtc-sys/build.rs` |
| C header | cbindgen config excludes JNI symbols; header committed | `livekit-ffi/cbindgen.toml`, `livekit-ffi/include/livekit_ffi.h` |
| Packaging | Conan 1.x recipe + build scripts; Azure Pipelines | `livekit-ffi/conan_assets/conanfile.py`, `livekit-ffi/generate_conan_build.{sh,bat}`, `.azure/pipelines/` |

Upstream sync procedure and full build instructions: [FORK_DOCUMENTATION.md](FORK_DOCUMENTATION.md).

## Run / build / test / lint

libwebrtc must be built (or `LK_CUSTOM_WEBRTC` pointed at a build) before any crate
that depends on `webrtc-sys` compiles. Details: [docs/runbooks/local-setup.md](docs/runbooks/local-setup.md).

```bash
# 1. libwebrtc for Android (from webrtc-sys/libwebrtc; needs ANDROID_HOME or ~/Android/Sdk)
cd webrtc-sys/libwebrtc && ./build_android.sh --arch arm64 --profile release

# 2. livekit-ffi for Android + Conan folder (needs ANDROID_NDK_HOME, cargo-ndk, cbindgen)
cd livekit-ffi && ./generate_conan_build.sh --platform android --arch arm64 --profile release

# 3. Export the Conan package (Conan 1.x)
cd livekit-ffi_conan && conan export-pkg . livekit-ffi/<version>@dn/stable -pr <profile> -f
```

```bash
cargo fmt -- --check          # same check as .github/workflows/format.yml
cargo test -p libwebrtc       # needs libwebrtc (LK_CUSTOM_WEBRTC or upstream download)
```

Testing details: [docs/runbooks/testing.md](docs/runbooks/testing.md). Release:
[docs/runbooks/release.md](docs/runbooks/release.md).

## Architecture overview

See [docs/architecture.md](docs/architecture.md) for diagrams and data flows, and
[docs/modules/](docs/modules/) for the two areas DisplayNote maintains:
[livekit-ffi](docs/modules/livekit-ffi.md) and
[webrtc-sys / libwebrtc build](docs/modules/webrtc-sys.md).

## Coding conventions

- Rust formatting: `rustfmt.toml` (`max_width = 100`, `use_small_heuristics = "Max"`); CI runs `cargo fmt -- --check`.
- Logging: Rust `log` crate macros (`log::info!`, `log::debug!`…), C++ `RTC_LOG(LS_*)`. No `tracing` macros in the shipped crates.
- FFI surface: new C functions go in `livekit-ffi/src/cabi.rs` as `#[no_mangle] pub extern "C"` and must be added to `livekit-ffi/include/livekit_ffi.h` (cbindgen output, committed).
- Comment DN-specific code with the reason and, where relevant, the ADO work item (see `strip_jni_zero.sh`, `lk_runtime.rs`).
- Commits (recent history): Conventional Commits with `AB#<id>` (`fix(android): AB#141676 …`); PRs merged into `main` on `DisplayNote/dn_livekit_ffi`.

## Where to add X

| If you are adding… | Go to | Follow |
|---|---|---|
| A new C entry point for the host | `livekit-ffi/src/cabi.rs` + `livekit-ffi/include/livekit_ffi.h` | `livekit_ffi_set_force_sw_h264` |
| A process-wide option read when the WebRTC factory is created | `livekit/src/rtc_engine/lk_runtime.rs` | `FORCE_SW_H264` (set under the `LK_RUNTIME` lock) |
| An Android encoder/decoder behaviour | `webrtc-sys/src/android/video_encoder_factory.cpp` / `video_decoder_factory.cpp` | JNI lookups with `RTC_LOG(LS_WARNING)` fallbacks |
| A libwebrtc source patch (Android) | `webrtc-sys/libwebrtc/patches/` + the `patches=(…)` list in `build_android.sh` | `sw_h264_fallback.patch` |
| A new Android ABI / Conan arch | `build_android.sh`, `generate_conan_build.sh`, `conan_assets/conanfile.py`, `.azure/pipelines/` | commit `8c795a97` (x86_64) |
| A protobuf request/event | `livekit-ffi/protocol/*.proto`, regenerate with `livekit-ffi/generate_proto.sh` | upstream pattern — avoid unless syncing upstream |

## Gotchas

- `livekit_ffi_set_force_sw_h264` only takes effect before the first `LkRuntime` (first room connection); later calls log a warning and are ignored (`lk_runtime.rs`).
- `strip_jni_zero.sh` must keep `JniInit`/`JniUtil`; removing them crashes the host with `ClassNotFoundException` at runtime, not at build time.
- `generate_conan_build.sh` builds Android with `webrtc-sys/use_x264`; the Azure Android builds (`.azure/pipelines/ffi-builds.yml`) use only `rustls-tls-webpki-roots`. The Windows `.bat` armv7 branch passes `webrtc-sys/x264`, a feature that does not exist in `webrtc-sys/Cargo.toml` (`use_x264`).
- Azure publishes to channel `dn/develop` (`prepare-conan-profile.yml`); the manual flow in `FORK_DOCUMENTATION.md` uses `dn/stable`.
- `FORK_DOCUMENTATION.md` names the upstream as `livekit/livekit-ffi`; the configured `upstream` remote is `livekit/rust-sdks`.
- `.gitmodules` declares `webrtc-sys/third_party/x264` but no gitlink is committed (and `**/third_party` is gitignored): clone x264 manually for `use_x264` builds (see local-setup).
- `build_android.sh` runs `git reset --hard` + `git clean -fd` inside `webrtc-sys/libwebrtc/src` on every run — never keep edits there; use patches.
- `livekit-ffi/src/server/tests.rs` is disabled (`//mod tests;` in `server/mod.rs`).
- With `capture_logs = true` the FFI logger forwards every level (including debug/trace) to the host — see [debugging-with-ai.md](docs/runbooks/debugging-with-ai.md).

## Glossary

See [docs/glossary.md](docs/glossary.md).

## External systems

| System | Role | Configured in |
|---|---|---|
| LiveKit server | Signalling (WebSocket) + media (WebRTC) | URL + token passed by the host in `ConnectRequest` |
| GitHub `DisplayNote/dn_livekit_ffi` | `origin` | — |
| GitHub `livekit/rust-sdks` | `upstream` (read-only for sync) | `FORK_DOCUMENTATION.md` |
| Chromium depot_tools / WebRTC sources | libwebrtc checkout | `webrtc-sys/libwebrtc/build_*.sh`, `.gclient` |
| videolan x264 | SW H264 encoder (submodule) | `.gitmodules`, `webrtc-sys/build.rs` |
| Azure Pipelines + `DisplayNote/qt-conan-ci@2.0.0` templates | Release build and Conan create/upload | `.azure/pipelines/pipeline.yml` |
| DN Conan remote | Package distribution | shared `qt-conan-ci` templates (not in this repo) |
