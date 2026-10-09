# Troubleshooting

| Symptom | Root cause | Fix |
|---|---|---|
| Host crashes at start with `ClassNotFoundException` for `org.jni_zero.JniInit` | `libwebrtc.jar` built without the jni_zero bootstrap classes (AB#141676) | Rebuild with the current `strip_jni_zero.sh`; it fails the build if `JniInit`/`JniUtil` are missing |
| D8 "defined multiple times" for `org.jni_zero.*` in the host APK | jni_zero classes not stripped | Ensure `build_android.sh` ran `strip_jni_zero.sh` |
| Linker errors for libwebrtc symbols | libwebrtc not built for this arch/profile, or `LK_CUSTOM_WEBRTC` wrong | Run `build_android.sh --arch … --profile …` first (FORK_DOCUMENTATION.md) |
| `x264 submodule not found at third_party/x264` panic | `.gitmodules` lists x264 but the tree has no gitlink for it, so `git submodule update` never fetches it | Clone x264 into `webrtc-sys/third_party/x264` ([local-setup.md](local-setup.md)) |
| `ANDROID_NDK_HOME must be set for Android builds` | x264 cross-build in `webrtc-sys/build.rs` | Export `ANDROID_NDK_HOME` |
| `build_android.sh` prints "Failed to apply even with 3-way merge" and continues | A patch no longer matches the WebRTC revision | Update the patch under `webrtc-sys/libwebrtc/patches/`; the script only warns |
| SW H264 not used although requested | `livekit_ffi_set_force_sw_h264` called after the first connect (warning logged by `lk_runtime.rs`), Android API < 29, or SW factory unavailable (warning from `AndroidVideoEncoderFactory`) | Call the setter before the first room connection |
| Windows `.bat` Android armv7 build fails on features | `.bat` passes `webrtc-sys/x264`; the feature is `use_x264` | Use `generate_conan_build.sh` for Android |
| Logs missing on the host | `capture_logs = false` → logs go to `env_logger` (stderr, `RUST_LOG`) | See [debugging-with-ai.md](debugging-with-ai.md) |
