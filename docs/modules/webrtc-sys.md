# Module: webrtc-sys and the libwebrtc build

Paths: `webrtc-sys/` (crate), `webrtc-sys/libwebrtc/` (build scripts and patches),
`webrtc-sys/build/` (crate `webrtc-sys-build`), plus the thin DN changes in
`libwebrtc/` (Rust wrapper).

## Purpose and boundaries

`webrtc-sys` is the cxx bridge between Rust and the native libwebrtc. DisplayNote
uses it to (a) build libwebrtc for Android with renamed Java packages, (b) add an
Android encoder/decoder factory with SW-H264 control, and (c) add an x264 encoder.

## DN components

| File | Responsibility |
|---|---|
| `webrtc-sys/libwebrtc/build_android.sh` | depot_tools + `gclient sync`, reset checkout, apply patches, run `migrate_webrtc.sh` / `webrtc_structure.sh`, GN/ninja build, `strip_jni_zero.sh`, copy artifacts to `android-<arch>-<profile>/` |
| `webrtc-sys/libwebrtc/migrate_webrtc.sh`, `webrtc_structure.sh` | Rewrite `org.webrtc` → `livekit.org.webrtc` and move sources |
| `webrtc-sys/libwebrtc/strip_jni_zero.sh` | Remove `org.jni_zero` from `libwebrtc.jar` except `JniInit`, `JniUtil` |
| `webrtc-sys/libwebrtc/patches/sw_h264_fallback.patch` | `HardwareVideoEncoderFactory` gains `allowSoftwareCodecs` |
| `webrtc-sys/src/android/video_encoder_factory.cpp` | `AndroidVideoEncoderFactory(force_sw_h264)`: HW / SW-H264 / x264 / builtin routing via JNI |
| `webrtc-sys/src/android/video_decoder_factory.cpp` | Android decoder factory |
| `webrtc-sys/src/x264/x264_video_encoder.cpp` | x264-based `webrtc::VideoEncoder` (feature `use_x264`; see `webrtc-sys/src/x264/README.md`) |
| `webrtc-sys/build.rs` | `setup_x264()` builds the submodule `third_party/x264` if the static lib is missing; Android links `c++_shared` |
| `libwebrtc/src/native/peer_connection_factory.rs` | `PeerConnectionFactory::new(force_sw_h264)`; installs the native log sink |

## Dependencies

- libwebrtc artefacts located through `LK_CUSTOM_WEBRTC` (`webrtc-sys/build/src/lib.rs`);
  without it `webrtc-sys-build` downloads upstream LiveKit prebuilt binaries from GitHub.
- Android: `ANDROID_NDK_HOME` (x264 cross-build and cargo-ndk), `ANDROID_HOME`/`ANDROID_SDK_ROOT` (libwebrtc build).

## Testing in isolation

`cargo test -p libwebrtc` runs `test_peer_connection_factory_force_sw_h264` and the
upstream tests on the host platform (needs a libwebrtc build or the upstream download).
The Android routing itself is only exercised on device through the host app.

## Typical changes

- New libwebrtc patch → add file under `patches/` and to the `patches=(…)` array.
- New Android ABI → `build_android.sh` arch list, `generate_conan_build.sh`,
  `conanfile.py` libdirs, `setup_x264()` target match, Azure stages.
