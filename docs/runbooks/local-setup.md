# Local setup

From a clean machine to a built `livekit-ffi` Conan folder. Tool list and the full
upstream-sync procedure: [FORK_DOCUMENTATION.md](../../FORK_DOCUMENTATION.md).

## 1. Clone

```bash
git clone --recurse-submodules git@github.com:DisplayNote/dn_livekit_ffi.git
cd dn_livekit_ffi
git submodule update --init --recursive   # livekit-protocol/protocol, yuv-sys/libyuv
# x264 is listed in .gitmodules but has no gitlink in the tree (and `**/third_party` is
# gitignored), so the command above does not fetch it. Android builds with use_x264 need it:
git clone https://code.videolan.org/videolan/x264.git webrtc-sys/third_party/x264
```

The x264 revision DN builds against is not recorded in the repository.

Run `/secret-scan-setup` once per clone (or `--global` once per machine for new clones) — commits containing secrets are blocked locally and in CI.
`/secret-scan-setup` is a Claude Code command from DisplayNote's `displaynote-engineering` plugin (install it with `/plugin install displaynote-engineering`); it is not part of this repository.

## 2. Tools

- Rust stable via rustup, plus `cargo install cargo-ndk cbindgen`.
- Android targets: `rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android`.
- Android NDK (`ANDROID_NDK_HOME`, also `ANDROID_NDK_ROOT`) and SDK (`ANDROID_HOME` / `ANDROID_SDK_ROOT`, or `~/Android/Sdk`).
- Python 3, git, Conan 1.x (the recipe uses `from conans import …`).
- `webrtc-sys/build.rs` builds x264 for Android with the NDK's `linux-x86_64` prebuilt toolchain, so Android builds expect a Linux host.

## 3. Build libwebrtc (once per arch/profile)

```bash
cd webrtc-sys/libwebrtc
./build_android.sh --arch arm64 --profile release    # arm | arm64 | x64
# Windows (cmd): build_windows.cmd --arch x64 --profile release
```

Output: `webrtc-sys/libwebrtc/android-<arch>-<profile>/` (libs, headers, `libwebrtc.jar`).
The first run clones depot_tools and syncs WebRTC (large download).

## 4. Build livekit-ffi and the Conan folder

```bash
cd livekit-ffi
./generate_conan_build.sh --platform android --arch arm64 --profile release
# Windows (cmd): generate_conan_build.bat --platform windows --lk_custom_webrtc <path-to-webrtc-build>
```

The `.sh` script sets `LK_CUSTOM_WEBRTC` to `../webrtc-sys/libwebrtc/android-<arch>-<profile>`,
regenerates `include/livekit_ffi.h` with cbindgen and fills `../livekit-ffi_conan/`
(gitignored). The `.bat` script requires `--lk_custom_webrtc`.

## 5. Host-side development without Android

For a desktop build of the Rust crates, point `LK_CUSTOM_WEBRTC` at a local libwebrtc
build (see `.vscode/tasks.json`, which uses `webrtc-sys/libwebrtc/mac-arm64-debug`) or
leave it unset to let `webrtc-sys-build` download LiveKit's upstream prebuilt binaries
(those do not contain the DN Android changes).
