#!/bin/sh

usage() {
    echo "Usage: $0 --platform <windows|android>"
    echo "Example: $0 --platform windows"
    exit 1
}

build_windows() {
    `cargo clean`
    `cargo build --release --target x86_64-pc-windows-msvc`
}

build_android() {
    "ln -sf $ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/lib/aarch64-unknown-linux-musl/{libunwind.so,libc++abi.a} $ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/lib/"

    # Build armv8
    `cargo clean`
    `cargo ndk --bindgen --target aarch64-linux-android build --release --no-default-features --features "rustls-tls-webpki-roots"`

    # Build armv7
    `cargo ndk --bindgen --target armv7-linux-androideabi build --release --no-default-features --features "rustls-tls-webpki-roots"`
}

create_folder_structure() {
    local target=$1
    if [ -z "$target" ]; then
        echo "Error: Target not specified"
        return 1
    fi

    cd $script_path
    cd ..
    # Create folder structure and copy files
    conan_dir="livekit-ffi_conan"
    mkdir -p "$conan_dir"
    mkdir -p "$conan_dir/lib"
    mkdir -p "$conan_dir/include"


    conan_assets_path="$script_path/conan_assets"
    # Copy conanfile.py (adjust the path as needed)
    cp "$conan_assets_path/conanfile.py" "$conan_dir/conanfile.py"

    case "$target" in
        *windows*)
            echo "Performing Windows-specific actions"
            # Windows-specific commands here
            mkdir -p "$conan_dir/lib/windows"
            cp "./target/$target/release/livekit_ffi.dll" "$conan_dir/lib/windows/livekit_ffi.dll"
            cp "./target/$target/release/livekit_ffi.lib" "$conan_dir/lib/windows/livekit_ffi.lib"
            ;;
        *android*)
            echo "Performing Android-specific actions"
            # Android-specific commands here
            case "$target" in
                aarch64-linux-android)
                    mkdir -p "$conan_dir/lib/android/arm64-v8a"
                    cp "./target/$target/release/liblivekit_ffi.so" "$conan_dir/lib/android/arm64-v8a/liblivekit_ffi.so"
                    cp "./target/$target/release/libwebrtc.jar" "$conan_dir/lib/android/arm64-v8a/libwebrtc.jar"
                    ;;
                armv7-linux-androideabi)
                    mkdir -p "$conan_dir/lib/android/armeabi-v7a"
                    cp "./target/$target/release/liblivekit_ffi.so" "$conan_dir/lib/android/armeabi-v7a/liblivekit_ffi.so"
                    cp "./target/$target/release/libwebrtc.jar" "$conan_dir/lib/android/armeabi-v7a/libwebrtc.jar"
                    ;;
                *)
                    echo "Error: Unrecognized target for Android. Must be aarch64-linux-android or armv7-linux-androideabi."
                    return 1
                    ;;
            esac
        *)
            echo "Error: Unrecognized target. Must contain 'windows' or 'android'."
            return 1
            ;;
    esac

    # Copy a file to include directory (adjust the path as needed)
    cp "$script_path/include/livekit_ffi.h" "$conan_dir/include/livekit_ffi.h"

    echo "Folder structure created and files copied successfully."
}

# Check if the correct number of arguments is provided
if [ $# -ne 2 ]; then
    usage
fi

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        --platform)
            platform="$2"
            shift # past argument
            shift # past value
            ;;
        *)
            usage
            ;;
    esac
done


initial_path=$(pwd)
script_path=$(dirname "$(readlink -f "$0")")

cd $script_path
# Generate protobuf files
"$script_path/generate_proto.sh"

# apply patchs
# cd $script_path
# cd ..

# patch_file="prefixed_webrtc.patch"

# if git apply "patchs/$patch_file"; then
#     echo "Applied patch"
# else
#     echo "Error applying patch"
#     cd "$initial_path"
#     exit 1
# fi

cd $script_path

case $platform in
    windows)
        echo "Performing build for Windows..."
        build_windows
        create_folder_structure "x86_64-pc-windows-msvc"
        ;;
    android)
        echo "Performing build for Android..."
        build_android
        create_folder_structure "aarch64-linux-android"
        create_folder_structure "armv7-linux-androideabi"
        ;;
    *)
        echo "Error: Unrecognized platform. Use 'windows' or 'android'."
        usage
        ;;
esac

# Come back to the current path
cd "$initial_path"
