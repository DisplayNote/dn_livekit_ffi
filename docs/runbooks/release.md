# Release

## Versioning

DN tags are `<upstream livekit-ffi version>.<DN patch>` on `main`: `0.12.34`,
`0.12.34.1`, `0.12.34.2` (current `main`). The crate version stays at upstream's
(`livekit-ffi/Cargo.toml`: `0.12.34`). Upstream `release-plz.toml` and
`.github/workflows/release.yml` are upstream release tooling, not DN's.

## Azure Pipelines (`.azure/pipelines/pipeline.yml`)

Triggered by any tag (branches excluded) and, since the file has no `pr:` section,
by pull requests through Azure's default PR trigger. Uses templates from
`DisplayNote/qt-conan-ci@refs/tags/2.0.0` and `DisplayNote/dn-pipeline-templates`
(tracked from `main`), and the `broadcast-environment-variables` variable group.

0. `common/setup.yml@ci` (VERSION), and in parallel the two blocking security gates
   from `dn-pipeline-templates` (AI Security 4.1): `SecretScan` (gitleaks over the full
   history, upstream included; accepted findings in `.gitleaksignore`) and
   `DependencyScan` (OSV-Scanner over every `Cargo.lock`; time-boxed exceptions in
   `osv-scanner.toml`). Both WebRTC stages depend on the two gates.
1. `webrtc-builds.yml` — libwebrtc: Windows x64, Android arm, arm64 and x64 (`--profile release`).
2. `ffi-builds.yml` — livekit-ffi: Windows `x86_64-pc-windows-msvc`, Android armv7, arm64 and x86_64 (`cargo ndk … --features "rustls-tls-webpki-roots"`, no `use_x264`).
3. `prepare-conan-profile.yml` — depends on both gates and every FFI build; copies `conanfile.py` and the committed `livekit_ffi.h`, runs Conan create for profiles `msvc19.x86_64`, `android.arm64-v8a`, `android.armeabi-v7a`, `android.x86_64` (debug + release) on channel `dn/develop` with version `$(Build.BuildNumber)`, then the shared upload template with `skipUpload` set when the source branch is a tag, and publishes the package as the `conan-package` pipeline artifact.

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
