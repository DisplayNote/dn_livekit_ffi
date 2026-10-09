# Glossary

| Term | Meaning |
|---|---|
| FFI server | `FfiServer` in `livekit-ffi/src/server/mod.rs`: handle table + tokio runtime behind the C ABI |
| FfiRequest / FfiResponse / FfiEvent | Protobuf messages exchanged with the host (`livekit-ffi/protocol/ffi.proto`) |
| Handle | `FfiHandleId` (u64) owning a Rust object or response buffer; released with `livekit_ffi_drop_handle` |
| `capture_logs` | `livekit_ffi_initialize` flag: forward Rust logs to the host as `LogBatch` events instead of `env_logger` |
| LogBatch / LogRecord | Protobuf log events (level, target, module_path, file, line, message) |
| LkRuntime | Process-wide holder of the `PeerConnectionFactory` (`livekit/src/rtc_engine/lk_runtime.rs`) |
| `force_sw_h264` | DN flag: prefer Android SW MediaCodec H264 (`c2.android.avc.encoder`) over HW |
| `LK_CUSTOM_WEBRTC` | Env var pointing `webrtc-sys` at a local libwebrtc build |
| `livekit.org.webrtc` | Renamed WebRTC Java package in the DN `libwebrtc.jar` |
| jni_zero | WebRTC's JNI bootstrap library (`org.jni_zero`), partly stripped by `strip_jni_zero.sh` |
| x264 | Open-source H264 encoder, submodule `webrtc-sys/third_party/x264`, feature `use_x264` |
| JoinResponse | First signalling reply: room, local + remote participants, ICE/TURN servers |
| Upstream | `livekit/rust-sdks` (remote `upstream`) |
| dnbroadcast-qt | DisplayNote Qt library that consumes this package for LiveKit streaming |
