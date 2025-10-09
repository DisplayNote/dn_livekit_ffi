#!/bin/bash

set -e # Exit immediately on error

usage() {
    echo "Usage: $0 --platform <windows|android> [--arch <arm64|arm>] [--build_type <debug|release>]"
    echo "Examples:"
    echo "  $0 --platform windows"
    echo "  $0 --platform android"
    echo "  $0 --platform android --arch arm64 --build_type debug"
    echo "  $0 --platform android --arch arm --build_type release"
    echo ""
    echo "Android options:"
    echo "  --arch <arm64|arm>        Architecture (default: arm64)"
    echo "  --build_type <debug|release>  Build type (default: release)"
    exit 1
}

build_windows() {
    cargo clean
    cargo build --release --target x86_64-pc-windows-msvc
    create_folder_structure "x86_64-pc-windows-msvc"
}

build_android() {
    local arch="$1"
    local build_type="$2"
    
    if [ -z "$ANDROID_NDK_HOME" ]; then
        echo "Error: ANDROID_NDK_HOME is not set. Please set it before running the script."
        exit 1
    fi

    # Generate the C header file using cbindgen
    # cbindgen --config cbindgen.toml --crate livekit-ffi --output include/livekit_ffi.h

    # Determine cargo build flags based on build_type
    local build_flags=""
    if [ "$build_type" = "release" ]; then
        build_flags="--release"
    fi

    # Path to the custom WebRTC build for Android arm64
    export LK_CUSTOM_WEBRTC="$(pwd)/../webrtc-sys/libwebrtc/android-$arch-$build_type"

    cargo clean

    if [ "$arch" = "arm64" ]; then
        # Build armv8 (arm64) - aligned with Qt's arm64-v8a
        cargo ndk --target aarch64-linux-android build $build_flags --platform 21 --no-default-features --features "rustls-tls-webpki-roots,webrtc-sys/use_x264"
        create_folder_structure "aarch64-linux-android" "$build_type"
    elif [ "$arch" = "arm" ]; then
        # Build armv7 (32-bit)
        cargo ndk --target armv7-linux-androideabi build $build_flags --platform 21 --no-default-features --features "rustls-tls-webpki-roots,webrtc-sys/use_x264"
        create_folder_structure "armv7-linux-androideabi" "$build_type"
    else
        echo "Error: Invalid architecture: $arch. Must be 'arm64' or 'arm'."
        exit 1
    fi
}

create_folder_structure() {
    local target=$1
    local build_type=${2:-release}  # Default to release if not specified

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
            cp "../target/$target/$build_type/liblivekit_ffi.so" "$conan_dir/lib/android/arm64-v8a/"
            cp "../target/$target/$build_type/libwebrtc.jar" "$conan_dir/lib/android/arm64-v8a/"
            ;;
        armv7-linux-androideabi)
            mkdir -p "$conan_dir/lib/android/armeabi-v7a"
            cp "../target/$target/$build_type/liblivekit_ffi.so" "$conan_dir/lib/android/armeabi-v7a/"
            cp "../target/$target/$build_type/libwebrtc.jar" "$conan_dir/lib/android/armeabi-v7a/"
            ;;
        *)
            echo "Error: Unrecognized target: $target"
            return 1
            ;;
    esac

    cp "$script_path/include/livekit_ffi.h" "$conan_dir/include/"

    echo "Folder structure created and files copied successfully for $target ($build_type)."
}

main() {
    if [ $# -lt 2 ]; then usage; fi

    local platform=""
    local arch="arm64"      # Default architecture for Android
    local build_type="release"  # Default build type
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --platform)
                platform="$2"
                shift 2
                ;;
            --arch)
                arch="$2"
                shift 2
                ;;
            --build_type)
                build_type="$2"
                shift 2
                ;;
            *)
                usage
                ;;
        esac
    done

    # Validate required platform parameter
    if [ -z "$platform" ]; then
        echo "Error: --platform is required"
        usage
    fi

    # Validate arch parameter for Android
    if [ "$platform" = "android" ] && [[ "$arch" != "arm64" && "$arch" != "arm" ]]; then
        echo "Error: Invalid architecture '$arch'. Must be 'arm64' or 'arm'."
        usage
    fi

    # Validate build_type parameter
    if [[ "$build_type" != "debug" && "$build_type" != "release" ]]; then
        echo "Error: Invalid build type '$build_type'. Must be 'debug' or 'release'."
        usage
    fi

    local initial_path=$(pwd)
    local script_path=$(dirname "$(readlink -f "$0")")

    cd "$script_path"

    case $platform in
        windows)
            build_windows
            ;;
        android)
            echo "Building Android for arch: $arch, build_type: $build_type"
            build_android "$arch" "$build_type"
            ;;
        *)
            usage
            ;;
    esac

    cd "$initial_path"
}

main "$@"
