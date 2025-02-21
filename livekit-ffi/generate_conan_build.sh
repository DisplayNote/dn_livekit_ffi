#!/bin/bash

set -e # Exit immediately on error

usage() {
    echo "Usage: $0 --platform <windows|android>"
    echo "Example: $0 --platform windows"
    exit 1
}

build_windows() {
    cargo clean
    cargo build --release --target x86_64-pc-windows-msvc
    create_folder_structure "x86_64-pc-windows-msvc"
}

build_android() {
    if [ -z "$ANDROID_NDK_HOME" ]; then
        echo "Error: ANDROID_NDK_HOME is not set. Please set it before running the script."
        exit 1
    fi

    ln -sf "$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/lib/aarch64-unknown-linux-musl/{libunwind.so,libc++abi.a}" \
        "$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/lib/"

    # Build armv8 (arm64)
    cargo clean
    cargo ndk --bindgen --target aarch64-linux-android build --release --no-default-features --features "rustls-tls-webpki-roots"
    create_folder_structure "aarch64-linux-android"

    # Build armv7 (32-bit)
    cargo clean
    cargo ndk --bindgen --target armv7-linux-androideabi build --release --no-default-features --features "rustls-tls-webpki-roots"
    create_folder_structure "armv7-linux-androideabi"
}

create_folder_structure() {
    local target=$1

    if [ -z "$target" ]; then
        echo "Error: Target not specified"
        return 1
    fi

    local conan_dir="../livekit-ffi_conan"
    mkdir -p "$conan_dir/lib" "$conan_dir/include"

    local conan_assets_path="$script_path/conan_assets"
    cp "$conan_assets_path/conanfile.py" "$conan_dir/conanfile.py"

    case "$target" in
        x86_64-pc-windows-msvc)
            mkdir -p "$conan_dir/lib/windows"
            cp "../target/$target/release/livekit_ffi.dll" "$conan_dir/lib/windows/"
            cp "../target/$target/release/livekit_ffi.dll.lib" "$conan_dir/lib/windows/livekit_ffi.lib"
            ;;
        aarch64-linux-android)
            mkdir -p "$conan_dir/lib/android/arm64-v8a"
            cp "../target/$target/release/liblivekit_ffi.so" "$conan_dir/lib/android/arm64-v8a/"
            cp "../target/$target/release/libwebrtc.jar" "$conan_dir/lib/android/arm64-v8a/"
            ;;
        armv7-linux-androideabi)
            mkdir -p "$conan_dir/lib/android/armeabi-v7a"
            cp "../target/$target/release/liblivekit_ffi.so" "$conan_dir/lib/android/armeabi-v7a/"
            cp "../target/$target/release/libwebrtc.jar" "$conan_dir/lib/android/armeabi-v7a/"
            ;;
        *)
            echo "Error: Unrecognized target: $target"
            return 1
            ;;
    esac

    cp "$script_path/include/livekit_ffi.h" "$conan_dir/include/"

    echo "Folder structure created and files copied successfully for $target."
}

main() {
    if [ $# -ne 2 ]; then usage; fi

    local platform=""
    while [[ $# -gt 0 ]]; do
        case $1 in
            --platform)
                platform="$2"
                shift 2
                ;;
            *)
                usage
                ;;
        esac
    done

    local initial_path=$(pwd)
    local script_path=$(dirname "$(readlink -f "$0")")

    cd "$script_path"

    case $platform in
        windows)
            build_windows
            ;;
        android)
            build_android
            ;;
        *)
            usage
            ;;
    esac

    cd "$initial_path"
}

main "$@"
