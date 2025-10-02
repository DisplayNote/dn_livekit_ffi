#!/usr/bin/env bash
# LiveKit WebRTC Android build with pre-build package migration
# Rewrites org.webrtc -> livekit.org.webrtc across sources prior to build.

set -euo pipefail

arch=""
profile="release"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --arch)
      arch="$2"
      if [ "$arch" != "arm" ] && [ "$arch" != "x64" ] && [ "$arch" != "arm64" ]; then
        echo "Error: Invalid value for --arch. Must be 'arm', 'x64' or 'arm64'." >&2
        exit 1
      fi
      shift 2
      ;;
    --profile)
      profile="$2"
      if [ "$profile" != "debug" ] && [ "$profile" != "release" ]; then
        echo "Error: Invalid value for --profile. Must be 'debug' or 'release'." >&2
        exit 1
      fi
      shift 2
      ;;
    *)
      echo "Error: Unknown argument '$1'" >&2
      exit 1
      ;;
  esac
done

if [ -z "$arch" ]; then
  echo "Error: --arch must be set." >&2
  exit 1
fi

echo "Building LiveKit WebRTC - Android"
echo "Arch: $arch"
echo "Profile: $profile"

# --- fetch depot_tools ---
if [ ! -e "$(pwd)/depot_tools" ]; then
  git clone --depth 1 https://chromium.googlesource.com/chromium/tools/depot_tools.git
fi
export COMMAND_DIR="$(cd "$(dirname "$0")"; pwd)"
export PATH="$(pwd)/depot_tools:$PATH"
export OUTPUT_DIR="$(pwd)/src/out-$arch-$profile"
export ARTIFACTS_DIR="$(pwd)/android-$arch-$profile"

# --- ensure .gclient configuration for android ---
echo "Updating existing .gclient file..."
if ! grep -q 'target_os.*=.*\[.*"android".*"unix".*\]' .gclient; then
  # Remove any existing target_os line
  sed -i '/^target_os\s*=/d' .gclient
  # Add the new target_os line
  echo 'target_os = ["android", "unix"]' >> .gclient
fi

# --- fetch src (WebRTC) ---
if [ ! -e "$(pwd)/src" ]; then
  echo "Setting up WebRTC Android checkout..."
  gclient sync
else
  echo "WebRTC checkout already exists, syncing dependencies..."

  # --- reset src and subrepos to clean state ---
  echo "Resetting WebRTC source to clean state..."

  # Reset main src directory
  pushd src >/dev/null
  echo "  Resetting main src repo..."
  git reset --hard HEAD
  git clean -fd

  # Reset all submodules/subrepos in src
  echo "  Resetting src submodules..."
  git submodule foreach --recursive 'git reset --hard HEAD && git clean -fd' || true
  popd >/dev/null

  # Reset build directory if it exists and is a git repo
  if [[ -d "src/build" && -d "src/build/.git" ]]; then
    echo "  Resetting build directory..."
    pushd src/build >/dev/null
    git reset --hard HEAD
    git clean -fd
    git submodule foreach --recursive 'git reset --hard HEAD && git clean -fd' || true
    popd >/dev/null
  fi

  # Reset buildtools directory if it exists and is a git repo
  if [[ -d "src/buildtools" && -d "src/buildtools/.git" ]]; then
    echo "  Resetting buildtools directory..."
    pushd src/buildtools >/dev/null
    git reset --hard HEAD
    git clean -fd
    git submodule foreach --recursive 'git reset --hard HEAD && git clean -fd' || true
    popd >/dev/null
  fi

  # Reset third_party directories that are commonly git repos
  for third_party_dir in "src/third_party/libc++" "src/third_party/libc++abi" "src/third_party/libunwind"; do
    if [[ -d "$third_party_dir" && -d "$third_party_dir/.git" ]]; then
      echo "  Resetting $(basename "$third_party_dir") in third_party..."
      pushd "$third_party_dir" >/dev/null
      git reset --hard HEAD
      git clean -fd
      popd >/dev/null
    fi
  done

  echo "WebRTC source reset complete."
fi

# Ensure Android SDK is properly set up
echo "Setting up Android SDK environment..."
if [[ -z "${ANDROID_HOME:-}" && -z "${ANDROID_SDK_ROOT:-}" ]]; then
  if [[ -d "$HOME/Android/Sdk" ]]; then
    export ANDROID_HOME="$HOME/Android/Sdk"
    export ANDROID_SDK_ROOT="$ANDROID_HOME"
    echo "  Detected Android SDK at $ANDROID_HOME"
  else
    echo "Error: ANDROID_HOME or ANDROID_SDK_ROOT is not set, and default location not found." >&2
    exit 1
  fi
else
  echo "  Using existing Android SDK environment variables."
fi

# --- apply patches (if any) ---
echo "Applying patches..."
pushd src >/dev/null

# List of patches to apply
patches=(
  # "add_licenses.patch"
  "ssl_verify_callback_with_native_handle.patch"
  "add_deps.patch"
  "android_use_libunwind.patch"
)

patch_failed=false
for patch in "${patches[@]}"; do
  patch_file="$COMMAND_DIR/patches/$patch"
  if [[ -f "$patch_file" ]]; then
    echo "Applying patch: $patch"
    if git apply "$patch_file" -v --ignore-space-change --ignore-whitespace --whitespace=nowarn; then
      echo "  ✓ Successfully applied: $patch"
    else
      echo "  ✗ Failed to apply: $patch"
      echo "  Attempting to apply with 3-way merge..."
      if git apply "$patch_file" --3way --ignore-space-change --ignore-whitespace --whitespace=nowarn; then
        echo "  ✓ Successfully applied with 3-way merge: $patch"
      else
        echo "  ✗ Failed to apply even with 3-way merge: $patch"
        echo "  WARNING: Continuing without this patch - build may fail"
        patch_failed=true
      fi
    fi
  else
    echo "  ⚠ Patch file not found: $patch_file"
  fi
done

if [[ "$patch_failed" == "true" ]]; then
  echo "WARNING: Some patches failed to apply. The build may not work correctly."
  echo "You may need to update the patches to match the current WebRTC version."
fi

popd >/dev/null
echo "Patch application complete."

# --- migrate org.webrtc -> livekit.org.webrtc before build ---
echo "Running package migration..."
"$COMMAND_DIR/migrate_webrtc.sh" "$(pwd)/src"

# --- create new package structure for migrated files ---
echo "Running package structure creation..."
"$COMMAND_DIR/create_package_structure.sh" src

# --- build setup ---
mkdir -p "$ARTIFACTS_DIR/lib"

debug="false"
if [ "$profile" = "debug" ]; then
  debug="true"
fi

args="is_debug=$debug \
  is_java_debug=$debug \
  target_os=\"android\" \
  target_cpu=\"$arch\" \
  rtc_enable_protobuf=false \
  treat_warnings_as_errors=false \
  use_custom_libcxx=false \
  rtc_include_tests=false \
  rtc_build_tools=false \
  rtc_build_examples=false \
  rtc_libvpx_build_vp9=false \
  is_component_build=false \
  enable_stripping=true \
  rtc_use_h264=false \
  rtc_use_pipewire=false \
  symbol_level=0 \
  enable_iterator_debugging=false \
  use_rtti=true"

# if [ "$debug" = "true" ]; then
#   args="${args} is_asan=true is_lsan=true"
# fi

# --- GN gen ---
gn gen "$OUTPUT_DIR" --root="src" --args="${args}"

# --- build ---
autoninja -C "$OUTPUT_DIR" :default \
  sdk/android:native_api \
  sdk/android:libwebrtc \
  sdk/android:libjingle_peerconnection_so

# --- archive static lib (exclude nasm objs) ---
ar -rc "$ARTIFACTS_DIR/lib/libwebrtc.a" \
  $(find "$OUTPUT_DIR/obj" -name '*.o' -not -path "*/third_party/nasm/*")

# --- (REMOVED) shadow packaging ---
# Previously: ./shadow_jar.sh ... org.webrtc -> livekit.org.webrtc
# Not needed; Java sources are already migrated pre-build.

# --- licenses ---
python3 "./src/tools_webrtc/libs/generate_licenses.py" \
  --target :default "$OUTPUT_DIR" "$OUTPUT_DIR"

# --- copy artifacts ---
cp "$OUTPUT_DIR/obj/webrtc.ninja" "$ARTIFACTS_DIR"
cp "$OUTPUT_DIR/libjingle_peerconnection_so.so" "$ARTIFACTS_DIR/lib"
cp "$OUTPUT_DIR/args.gn" "$ARTIFACTS_DIR"
cp "$OUTPUT_DIR/lib.java/sdk/android/libwebrtc.jar" "$ARTIFACTS_DIR/libwebrtc.jar"
cp "src/sdk/android/AndroidManifest.xml" "$ARTIFACTS_DIR"

# --- headers ---
pushd src >/dev/null
find . -name "*.h" -print | cpio -pd "$ARTIFACTS_DIR/include"
find . -name "*.inc" -print | cpio -pd "$ARTIFACTS_DIR/include"
popd >/dev/null

echo "Done. Artifacts in: $ARTIFACTS_DIR"
