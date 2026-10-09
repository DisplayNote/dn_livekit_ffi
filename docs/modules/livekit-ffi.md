# Module: livekit-ffi

Path: `livekit-ffi/` — crate `livekit-ffi` 0.12.34, `crate-type = ["lib", "cdylib"]`.

## Purpose and boundaries

The C ABI library the host app links. It owns the FFI server (handle table, tokio
runtime, logger) and translates protobuf requests into `livekit` SDK calls. Room /
signalling / WebRTC logic belongs in `livekit`, `livekit-api`, `libwebrtc`,
`webrtc-sys`, not here.

## Public API (C, `include/livekit_ffi.h`)

| Function | Notes |
|---|---|
| `livekit_ffi_initialize(cb, capture_logs, sdk, sdk_version)` | Register the event callback; `capture_logs` routes logs to the host |
| `livekit_ffi_request(data, len, &res_ptr, &res_len)` | Protobuf `FfiRequest` in, `FfiResponse` out; returns a handle owning the response buffer |
| `livekit_ffi_drop_handle(handle)` | Release any FFI handle |
| `livekit_ffi_set_force_sw_h264(force)` | **DN** — call before the first connect; ignored on non-Android |
| `livekit_ffi_dispose()` | Close rooms, stop log capture |

`JNI_OnLoad` (Android) is exported from `src/cabi.rs` but excluded from the header by
`cbindgen.toml`. Protobuf schemas: `protocol/*.proto` (generated Rust in
`src/livekit.proto.rs`, regenerate with `generate_proto.sh`).

## Dependencies

- Upstream: `livekit`, `webrtc-sys` (features `use_vaapi`, `use_nvidia`; Android
  builds add `webrtc-sys/use_x264` via `generate_conan_build.sh`), `soxr-sys`, `imgproc`,
  `livekit-protocol`, `env_logger`, `log`, `tokio`.
- Downstream: dnbroadcast-qt via the Conan package.

## Packaging files (DN)

- `conan_assets/conanfile.py` — Conan 1.x recipe (`livekit-ffi`, settings os/compiler/build_type/arch; libdirs per Android ABI).
- `generate_conan_build.sh` (Android) / `generate_conan_build.bat` (Windows + Android) — set `LK_CUSTOM_WEBRTC`, `cargo clean`, build, copy into `../livekit-ffi_conan/`.
- `cbindgen.toml` — header generation (`generate_conan_build.sh` runs cbindgen for Android).

## Testing in isolation

`src/server/tests.rs` is currently disabled (`//mod tests;` in `src/server/mod.rs`).
There is no runnable unit test in this crate; see [../runbooks/testing.md](../runbooks/testing.md).

## Typical changes

- New C function → `src/cabi.rs` + `include/livekit_ffi.h` (keep the header in sync; the Azure pipeline copies the committed header into the package).
- New logging → follow the rules in [../runbooks/debugging-with-ai.md](../runbooks/debugging-with-ai.md); every level reaches the host when `capture_logs` is on.
