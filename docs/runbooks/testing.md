# Testing

## What exists

| Level | Where | Notes |
|---|---|---|
| Unit (Rust) | `libwebrtc/src/native/peer_connection_factory.rs` (`test_peer_connection_factory_force_sw_h264`, DN), `libwebrtc/src/peer_connection.rs`, `webrtc-sys/src/jsep.rs`, `webrtc-sys/src/rtc_error.rs`, `livekit/` | Run on the host platform |
| FFI | `livekit-ffi/src/server/tests.rs` | Disabled: `//mod tests;` in `livekit-ffi/src/server/mod.rs` |
| E2E (upstream) | `livekit/tests/` | Needs `livekit-server --dev` and `--features __lk-e2e-test` (`livekit/tests/README.md`) |
| On device | — | Android encoder routing (`webrtc-sys/src/android/`) is only exercised through the host app |

## Commands

```bash
cargo fmt -- --check
cargo test -p libwebrtc
cargo test -p livekit
# E2E (upstream)
livekit-server --dev &
cargo test --features __lk-e2e-test
```

All of them compile `webrtc-sys`, which needs `LK_CUSTOM_WEBRTC` or network access for
the upstream prebuilt download.

## CI

- `.github/workflows/tests.yml` (upstream, push/PR to `main`): `cargo +nightly test --release` with `RUST_LOG=info` and `--nocapture`.
- `.github/workflows/format.yml`: `cargo fmt -- --check`.
- Azure Pipelines (`.azure/pipelines/`) only build and package; they run no tests.

## Adding a test

Follow `test_peer_connection_factory_force_sw_h264`: a `#[tokio::test]` in the module's
`mod tests`, initialising `env_logger::builder().is_test(true).try_init()`.
