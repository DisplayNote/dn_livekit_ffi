# LiveKit-FFI Fork for WebRTC with livekit.org.webrtc Prefix

This repository is a fork of [livekit-ffi](https://github.com/livekit/livekit-ffi). 

---

This fork ensures compatibility with projects requiring multiple WebRTC implementations while maintaining seamless integration with Conan package management.

---

## Modifications Done with Reference to upstream/main (Original Repo)

The main modifications in this fork compared to the original repository include:

- **WebRTC Package Prefix**: Modified WebRTC libraries to use `livekit.org.webrtc` prefix instead of the default `org.webrtc`
- **Android Library Integration**: Updated Android build configurations to support dual WebRTC library integration
- **Conan Package Support**: Enhanced Conan package generation and export processes
- **Build System Adjustments**: Modified build scripts and configurations to accommodate the prefix changes
- **Dependency Management**: Updated dependency declarations to prevent conflicts with other WebRTC implementations

## Dependencies and Tools

Before building this project, ensure you have the following dependencies and tools installed:

### Required Tools:
- **Rust**: Latest stable version (install via [rustup](https://rustup.rs/))
    - **cargo-ndk**: For Android NDK integration (install via `cargo install cargo-ndk`)
    - **cbindgen**: For C binding generation (install via `cargo install cbindgen`)
- **Python**: 3.7 or higher
- **CMake**: 3.16 or higher
- **Git**: For version control and repository management
- **Conan**: Package manager for C/C++ (install via `pip install conan`)

### Platform-specific Dependencies:

#### Linux:
```sh
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install build-essential pkg-config libssl-dev
```

#### Windows:
- Visual Studio 2019 or 2022 with C++ development tools
- Windows SDK 10

#### Android:
- Android NDK r23 or higher (align with current in use)
- Android SDK with API level +21 (align with current in use)
- Android SDK Platform Tools
- Java Development Kit (JDK) +17

### Rust Additional Tools and Targets:
```sh
# Install required Rust tools
cargo install cargo-ndk
cargo install cbindgen

# Add required Rust targets for cross-compilation
rustup target add aarch64-linux-android
rustup target add armv7-linux-androideabi
rustup target add i686-linux-android
rustup target add x86_64-linux-android
```

## Update from upstream

To get new changes from upstream branch we must to:

### 1. Add upstream remote (if not already added)
First, ensure the upstream remote is configured to point to the original repository:
```sh
git remote add upstream https://github.com/livekit/livekit-ffi.git
```

You can verify the remote is added correctly:
```sh
git remote -v
```

### 2. Create a new support branch
Create a new branch from `main` called `support/ffi-vx.xx.xx` in order to get the changes there.
```sh
git checkout -b support/ffi-v0.13.0
```

### 3. Fetch changes from upstream
Get all new changes from upstream:
```sh
git fetch upstream --tags
```

### 4. Rebase onto upstream changes
Do a rebase:
```sh
git rebase ffi-v0.13.0
```

### 5. Resolve conflicts and continue
If there are conflicts during the rebase, you must resolve them and then continue:

```sh
# After resolving conflicts in your editor
git add .
git rebase --continue
```

If you want to apply the rebase without stopping for conflicts (use with caution):
```sh
git rebase --apply
```

## Steps to Build WebRTC

WebRTC needs to be built first before building livekit-ffi. Follow these steps:

### 1. Navigate to WebRTC Build Directory
```sh
cd webrtc-sys/libwebrtc
```

### 2. Build WebRTC for Different Platforms

#### For macOS (ARM64):
```sh
./build_macos.sh --arch arm64|x64 --profile debug|release
```

#### For Android:
```sh
./build_android.sh --arch arm|arm64|x64 --profile debug|release
```

#### For Windows:
```sh
# From Windows command prompt or PowerShell
build_windows.bat --arch arm64|x64 --profile debug|release
```

### 3. Verify WebRTC Build
After successful build, you should see the compiled libraries in:
- `webrtc-sys/libwebrtc/{platform}-{arch}-{profile}/lib/`

## Steps to Build livekit-ffi and Create Conan Packages

**IMPORTANT:** Before proceeding with livekit-ffi build, you **MUST** complete the WebRTC build process first (see previous section). The livekit-ffi build depends on the compiled WebRTC libraries and will fail if they are not present.

The livekit-ffi build is integrated with the Conan package creation process through the `generate_conan_build` script. This script automatically configures the build environment and compiles livekit-ffi for the target platforms.

### 1. Prerequisites

Ensure that:
- **WebRTC libraries are built for all required platforms** (MANDATORY - see "Steps to Build WebRTC" section above)
- Conan is installed and configured
- Required environment variables are set (see below)

### 2. Set Required Environment Variables

For Android builds, you must have:
```sh
# Android NDK path (required for Android builds)
export ANDROID_NDK_ROOT="/path/to/android-ndk"
export ANDROID_NDK_HOME="/path/to/android-ndk"
```

**Note:** The `generate_conan_build` script will automatically configure `LK_CUSTOM_WEBRTC` to point to the appropriate WebRTC build based on the platform and architecture being built. This requires that WebRTC libraries have been successfully compiled first.

### 3. Generate Conan Build Directory and Build livekit-ffi

The `generate_conan_build` script performs the following actions:
- Configures `LK_CUSTOM_WEBRTC` environment variable automatically
- Builds livekit-ffi for the specified platform
- Creates the Conan package structure
- Generates the necessary build artifacts

#### Windows:
```sh
generate_conan_build.bat --platform windows
```

#### Linux:
```sh
./generate_conan_build.sh --platform android --arch arm|arm64 --profile debug|release
```

**Important Notes:**
- **WebRTC must be built first**: Ensure WebRTC libraries are compiled for your target platform before running this step
- Windows builds cannot be compiled from Linux
- The script will automatically detect and use the appropriate WebRTC build (if available)
- For Android builds, ensure `ANDROID_NDK_HOME` is properly set before running
- If WebRTC libraries are missing, the build will fail with linking errors

### 4. Verify Conan Package Structure
After execution, a `livekit-ffi_conan` directory will be created at the root of the project, containing:
- `conanfile.py` - Package configuration
- `include/` - Header files
- `lib/` - Compiled libraries for different platforms/architectures

### 5. Export Conan Packages

Navigate to the generated conan directory:
```sh
cd livekit-ffi_conan
```

Export the package for all different profiles:

```sh
conan export-pkg . livekit-ffi/{version}@dn/stable -pr {profile} -f
```

**Note:** Replace `{version}` and `{profile}` with the appropriate values.

### 6. Upload to Conan Repository

Upload the package to your Conan repository:
```sh
conan upload livekit-ffi/{version}@dn/stable -r dn --all
```

### 7. Verify Package Upload
Verify that the package was uploaded successfully:
```sh
conan search livekit-ffi/{version}@dn/stable -r dn
```

**Note:** Replace `{version}` with the appropriate tag version as needed for your release.
