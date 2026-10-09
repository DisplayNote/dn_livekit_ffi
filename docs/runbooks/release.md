# Release

## Versioning

DN tags are `<upstream livekit-ffi version>.<DN patch>` on `main`: `0.12.34`,
`0.12.34.1`, `0.12.34.2` (current `main`). The crate version stays at upstream's
(`livekit-ffi/Cargo.toml`: `0.12.34`). Upstream `release-plz.toml` and
`.github/workflows/release.yml` are upstream release tooling, not DN's.

## Azure Pipelines (`.azure/pipelines/pipeline.yml`)

Triggered by any tag (branches excluded). Uses templates from
`DisplayNote/qt-conan-ci@refs/tags/2.0.0` and the `broadcast-environment-variables`
variable group.

1. `webrtc-builds.yml` — libwebrtc: Windows x64, Android arm, Android arm64 (`--profile release`).
2. `ffi-builds.yml` — livekit-ffi: Windows `x86_64-pc-windows-msvc`, Android armv7, Android arm64 (`cargo ndk … --features "rustls-tls-webpki-roots"`, no `use_x264`).
3. `prepare-conan-profile.yml` — copies `conanfile.py` and the committed `livekit_ffi.h`, runs Conan create for profiles `msvc19.x86_64`, `android.arm64-v8a`, `android.armeabi-v7a` (debug + release) on channel `dn/develop` with version `$(Build.BuildNumber)`, then the shared upload template with `skipUpload` set when the source branch is a tag, and publishes the package as the `conan-package` pipeline artifact.

Android x86_64 is not built by the pipeline.

## Manual flow

`FORK_DOCUMENTATION.md` §"Steps to Build livekit-ffi and Create Conan Packages":
build libwebrtc, run `generate_conan_build.sh`, then from `livekit-ffi_conan/`:

```bash
conan export-pkg . livekit-ffi/<version>@dn/stable -pr <profile> -f
conan upload livekit-ffi/<version>@dn/stable -r dn --all
```

## Checklist

- `livekit-ffi/include/livekit_ffi.h` matches `src/cabi.rs` (the pipeline packages the committed header).
- `cargo fmt -- --check` passes.
- dnbroadcast-qt's Conan reference updated to the new version.
