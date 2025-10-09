#!/bin/bash

set -e # Exit immediately on error

usage() {
    echo "Usage: $0 --platform <windows|android> --lk_custom_webrtc <path>"
    echo "Example: $0 --platform windows --lk_custom_webrtc /path/to/webrtc"
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

    # Generate the C header file using cbindgen
    cbindgen --config cbindgen.toml --crate livekit-ffi --output include/livekit_ffi.h

    # Path to the custom WebRTC build for Android arm64
    export LK_CUSTOM_WEBRTC="$(pwd)/../webrtc-sys/libwebrtc/android-arm64-release"

    # Build armv8 (arm64) - aligned with Qt's arm64-v8a
    cargo clean
    cargo ndk --target aarch64-linux-android build --release --platform 21 --no-default-features --features "rustls-tls-webpki-roots,webrtc-sys/use_x264"
    create_folder_structure "aarch64-linux-android"

    # Path to the custom WebRTC build for Android arm
    export LK_CUSTOM_WEBRTC="$(pwd)/../webrtc-sys/libwebrtc/android-arm-release"

    # Build armv7 (32-bit)
    cargo clean
    cargo ndk --target armv7-linux-androideabi build --release --platform 21 --no-default-features --features "rustls-tls-webpki-roots,webrtc-sys/use_x264"
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
    if [ $# -lt 4 ]; then usage; fi

    local platform=""
    local lk_custom_webrtc=""
    while [[ $# -gt 0 ]]; do
        case $1 in
            --platform)
                platform="$2"
                shift 2
                ;;
            --lk_custom_webrtc)
                lk_custom_webrtc="$2"
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

    if [[ -z "$lk_custom_webrtc" ]]; then
        echo "Error: --lk_custom_webrtc is required."
        usage
    fi

    export LK_CUSTOM_WEBRTC="$lk_custom_webrtc"

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
