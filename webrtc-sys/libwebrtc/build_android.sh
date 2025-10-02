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
migrate_webrtc() {
  local root="$1"
  if [[ ! -d "$root" ]]; then
    echo "migrate_webrtc: '$root' is not a directory" >&2
    return 1
  fi
  echo "Running migrate_webrtc in: $root"

  # WebRTC-related folders to process (avoids unnecessary processing of unrelated code)
  local webrtc_folders=(
    "sdk"
    "api" 
    "modules/audio_device/android"
    "modules/audio_coding/audio_network_adaptor"
    "modules/video_capture/android"
    "modules/video_coding/codecs/h264/android"
    "modules/video_coding/codecs/vp8/android"
    "modules/video_coding/codecs/vp9/android"
    "rtc_base"
    "examples/android*"
    "test/android"    
  )

  # File types to process
  local exts=(
    "*.java" "*.kt" "*.xml" "*.gn" "*.gni" "*.proto"
    "*.c" "*.cc" "*.cpp" "*.cxx" "*.hpp" "*.hh" "*.h" "*.hxx"
    "*.m" "*.mm" "*.gradle" "*.properties" "*.mk" "*.cmake"
  )

  local find_expr=()
  for i in "${!exts[@]}"; do
    if [[ $i -gt 0 ]]; then find_expr+=(-o); fi
    find_expr+=(-name "${exts[$i]}")
  done

  local changed=0
  local total_files=0

  # Helper function to process a single folder
  process_folder() {
    local folder_path="$1"
    local folder_files=0
    
    echo "    Starting to process folder: $folder_path"
    
    # Check if folder exists and is accessible
    if [[ ! -d "$folder_path" ]]; then
      echo "    Error: Folder does not exist: $folder_path"
      return 1
    fi
    
    # Create find command and test it first
    local find_cmd="find \"$folder_path\" -type f \\( ${find_expr[*]} \\) -print0 2>/dev/null"
    echo "    Find command: $find_cmd"
    
    # Use safer approach without process substitution
    local temp_list
    temp_list="$(mktemp)"
    
    if ! find "$folder_path" -type f \( "${find_expr[@]}" \) -print0 2>/dev/null > "$temp_list"; then
      echo "    Warning: Find command failed for $folder_path"
      rm -f "$temp_list"
      return 0
    fi
    
    # Process files from the temp list
    while IFS= read -r -d '' file; do
      if [[ -z "$file" ]]; then
        continue
      fi
      
      local tmp
      tmp="$(mktemp)"
      if ! cp "$file" "$tmp" 2>/dev/null; then
        echo "    Warning: Failed to copy $file, skipping"
        rm -f "$tmp"
        continue
      fi
      
      ((total_files++))
      ((folder_files++))

      # Dot-notation and slash-notation replacements with double-prefix protection
      if ! perl -0777 -i -pe '
        s/(?<!livekit\.)\borg\.webrtc\b/livekit.org.webrtc/g;
        s{(?<!livekit/)org/webrtc\b}{livekit/org/webrtc}g;
        s{L(?<!livekit/)org/webrtc/}{Llivekit/org/webrtc/}g;
        s/package="org\.webrtc"/package="livekit.org.webrtc"/g;
        s/android:name="org\.webrtc"/android:name="livekit.org.webrtc"/g;
        s/(?<!livekit_)org_webrtc(?!_)/livekit_org_webrtc/g;
        s/(?<!livekit_)org_webrtc_/livekit_org_webrtc_/g;
        s/Java_(?<!livekit_)org_webrtc_/Java_livekit_org_webrtc_/g;
        s/_(?<!livekit_)org_webrtc_/_livekit_org_webrtc_/g;
        s/(?<!livekit_)org_webrtc_([A-Za-z0-9_]+)_clazz/livekit_org_webrtc_$1_clazz/g;
      ' "$file" 2>/dev/null; then
        echo "    Warning: Failed to process $file with perl, skipping"
        rm -f "$tmp"
        continue
      fi
      

      if ! cmp -s "$file" "$tmp" 2>/dev/null; then
        echo "    updated: $file"
        ((changed++))
      fi
      rm -f "$tmp"
    done < "$temp_list"
    
    rm -f "$temp_list"
    echo "    processed $folder_files files in $(basename "$folder_path")"
    return 0
  }

  # Process each WebRTC-related folder
  for folder in "${webrtc_folders[@]}"; do
    echo "  Checking folder: $folder"
    
    # Handle wildcard patterns by expanding them
    if [[ "$folder" == *"*"* ]]; then
      echo "    Expanding wildcard pattern: $folder"
      # Use shell globbing for wildcard patterns
      local found_folders=()
      if pushd "$root" >/dev/null 2>&1; then
        shopt -s nullglob  # Enable nullglob to handle no matches
        for expanded_folder in $folder; do
          if [[ -d "$expanded_folder" ]]; then
            found_folders+=("$expanded_folder")
            echo "    Found: $expanded_folder"
          fi
        done
        shopt -u nullglob  # Disable nullglob
        popd >/dev/null 2>&1
      else
        echo "    Warning: Failed to change to directory $root"
        continue
      fi
      
      # Process each expanded folder
      if [[ ${#found_folders[@]} -eq 0 ]]; then
        echo "    No folders found matching pattern: $folder"
      else
        for expanded_folder in "${found_folders[@]}"; do
          local folder_path="$root/$expanded_folder"
          echo "  Processing folder: $expanded_folder"
          if ! process_folder "$folder_path"; then
            echo "    Warning: Failed to process folder $expanded_folder"
          fi
        done
      fi
    else
      # Handle regular folder paths
      local folder_path="$root/$folder"
      if [[ -d "$folder_path" ]]; then
        echo "  Processing folder: $folder"
        if ! process_folder "$folder_path"; then
          echo "    Warning: Failed to process folder $folder"
        fi
      else
        echo "  Skipping non-existent folder: $folder"
      fi
    fi
  done

  echo "migrate_webrtc: processed $total_files files, updated $changed files"
}

migrate_webrtc "$(pwd)/src"

# --- create new package structure for migrated files ---
echo "Creating new package directory structure..."
pushd src >/dev/null

# Find all directories containing org/webrtc structure
find . -type d -path "*/org/webrtc" | while read -r webrtc_dir; do
  # Get the parent directory (e.g., ./sdk/android/src/java)
  parent_dir=$(dirname "$(dirname "$webrtc_dir")")
  
  # Create the new livekit/org/webrtc structure
  new_dir="$parent_dir/livekit/org/webrtc"
  if [[ ! -d "$new_dir" ]]; then
    echo "  Creating directory: $new_dir"
    mkdir -p "$new_dir"
    
    # Move all files and subdirectories from org/webrtc to livekit/org/webrtc
    if [[ -d "$webrtc_dir" ]]; then
      echo "  Moving contents from $webrtc_dir to $new_dir"
      mv "$webrtc_dir"/* "$new_dir/" 2>/dev/null || true
      
      # Remove the now-empty org/webrtc directory
      rmdir "$webrtc_dir" 2>/dev/null || true
      
      # Clean up empty parent directories if they exist
      org_dir=$(dirname "$webrtc_dir")
      if [[ -d "$org_dir" && -z "$(ls -A "$org_dir" 2>/dev/null)" ]]; then
        rmdir "$org_dir" 2>/dev/null || true
      fi
    fi
  fi
done

popd >/dev/null
echo "Package structure creation complete."

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
