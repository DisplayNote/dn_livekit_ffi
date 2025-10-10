// Copyright 2023 LiveKit, Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

use std::path::Path;
use std::path::PathBuf;
use std::{env, path, process::Command};

fn main() {
    if env::var("DOCS_RS").is_ok() {
        return;
    }

    println!("cargo:rerun-if-env-changed=LK_DEBUG_WEBRTC");
    println!("cargo:rerun-if-env-changed=LK_CUSTOM_WEBRTC");

    let mut builder = cxx_build::bridges([
        "src/peer_connection.rs",
        "src/peer_connection_factory.rs",
        "src/media_stream.rs",
        "src/media_stream_track.rs",
        "src/audio_track.rs",
        "src/video_track.rs",
        "src/data_channel.rs",
        "src/frame_cryptor.rs",
        "src/jsep.rs",
        "src/candidate.rs",
        "src/rtp_parameters.rs",
        "src/rtp_sender.rs",
        "src/rtp_receiver.rs",
        "src/rtp_transceiver.rs",
        "src/rtc_error.rs",
        "src/webrtc.rs",
        "src/video_frame.rs",
        "src/video_frame_buffer.rs",
        "src/helper.rs",
        "src/yuv_helper.rs",
        "src/audio_resampler.rs",
        "src/android.rs",
        "src/prohibit_libsrtp_initialization.rs",
        "src/apm.rs",
    ]);

    builder.files(&[
        "src/peer_connection.cpp",
        "src/peer_connection_factory.cpp",
        "src/media_stream.cpp",
        "src/media_stream_track.cpp",
        "src/audio_track.cpp",
        "src/video_track.cpp",
        "src/data_channel.cpp",
        "src/jsep.cpp",
        "src/candidate.cpp",
        "src/rtp_receiver.cpp",
        "src/rtp_sender.cpp",
        "src/rtp_transceiver.cpp",
        "src/rtp_parameters.cpp",
        "src/rtc_error.cpp",
        "src/webrtc.cpp",
        "src/video_frame.cpp",
        "src/video_frame_buffer.cpp",
        "src/video_encoder_factory.cpp",
        "src/video_decoder_factory.cpp",
        "src/audio_device.cpp",
        "src/audio_resampler.cpp",
        "src/frame_cryptor.cpp",
        "src/global_task_queue.cpp",
        "src/prohibit_libsrtp_initialization.cpp",
        "src/apm.cpp",
    ]);

    let webrtc_dir = webrtc_sys_build::webrtc_dir();
    let webrtc_include = webrtc_dir.join("include");
    let webrtc_lib = webrtc_dir.join("lib");

    if !webrtc_dir.exists() {
        webrtc_sys_build::download_webrtc().unwrap();
    }

    builder.includes(&[
        path::PathBuf::from("./include"),
        webrtc_include.clone(),
        webrtc_include.join("third_party/abseil-cpp/"),
        webrtc_include.join("third_party/libyuv/include/"),
        webrtc_include.join("third_party/libc++/"),
        // For mac & ios
        webrtc_include.join("sdk/objc"),
        webrtc_include.join("sdk/objc/base"),
    ]);
    builder.define("WEBRTC_APM_DEBUG_DUMP", "0");

    println!("cargo:rustc-link-search=native={}", webrtc_lib.to_str().unwrap());

    for (key, value) in webrtc_sys_build::webrtc_defines() {
        let value = value.as_deref();
        builder.define(key.as_str(), value);
    }

    // Link webrtc library
    println!("cargo:rustc-link-lib=static=webrtc");

    let target_os = env::var("CARGO_CFG_TARGET_OS").unwrap();
    let target_arch = env::var("CARGO_CFG_TARGET_ARCH").unwrap();
    match target_os.as_str() {
        "windows" => {
            println!("cargo:rustc-link-lib=dylib=msdmo");
            println!("cargo:rustc-link-lib=dylib=wmcodecdspuuid");
            println!("cargo:rustc-link-lib=dylib=dmoguids");
            println!("cargo:rustc-link-lib=dylib=crypt32");
            println!("cargo:rustc-link-lib=dylib=iphlpapi");
            println!("cargo:rustc-link-lib=dylib=ole32");
            println!("cargo:rustc-link-lib=dylib=secur32");
            println!("cargo:rustc-link-lib=dylib=winmm");
            println!("cargo:rustc-link-lib=dylib=ws2_32");
            println!("cargo:rustc-link-lib=dylib=strmiids");
            println!("cargo:rustc-link-lib=dylib=d3d11");
            println!("cargo:rustc-link-lib=dylib=gdi32");
            println!("cargo:rustc-link-lib=dylib=dxgi");
            println!("cargo:rustc-link-lib=dylib=dwmapi");
            println!("cargo:rustc-link-lib=dylib=shcore");

            //let path = env::current_dir().unwrap();
            //println!("cargo:rustc-link-search=native={}/vaapi-windows/x64/lib", path.display());
            //println!("cargo:rustc-link-lib=dylib=va");
            //println!("cargo:rustc-link-lib=dylib=va_win32");

            builder
                //.include("./vaapi-windows/DirectX-Headers-1.0/include")
                //.include(path::PathBuf::from("./vaapi-windows/x64/include"))
                //.file("vaapi-windows/DirectX-Headers-1.0/src/dxguids.cpp")
                //.file("src/vaapi/vaapi_display_win32.cpp")
                //.file("src/vaapi/vaapi_h264_encoder_wrapper.cpp")
                //.file("src/vaapi/vaapi_encoder_factory.cpp")
                //.file("src/vaapi/h264_encoder_impl.cpp")
                .flag("/std:c++20")
                //.flag("/wd4819")
                //.flag("/wd4068")
                .flag("/EHsc");
        }
        "linux" => {
            println!("cargo:rustc-link-lib=dylib=rt");
            println!("cargo:rustc-link-lib=dylib=dl");
            println!("cargo:rustc-link-lib=dylib=pthread");
            println!("cargo:rustc-link-lib=dylib=m");

            #[cfg(feature = "use_x264")]
            {
                // x264 on Linux also needs math library
                println!("cargo:rustc-link-lib=dylib=m");
            }

            match target_arch.as_str() {
                "x86_64" => {
                    #[cfg(feature = "use_vaapi")]
                    builder
                        .file("src/vaapi/vaapi_display_drm.cpp")
                        .file("src/vaapi/vaapi_h264_encoder_wrapper.cpp")
                        .file("src/vaapi/vaapi_encoder_factory.cpp")
                        .file("src/vaapi/h264_encoder_impl.cpp")
                        .file("src/vaapi/implib/libva-drm.so.init.c")
                        .file("src/vaapi/implib/libva-drm.so.tramp.S")
                        .file("src/vaapi/implib/libva.so.init.c")
                        .file("src/vaapi/implib/libva.so.tramp.S")
                        .flag("-DUSE_VAAPI_VIDEO_CODEC=1");

                    #[cfg(feature = "use_nvidia")]
                    builder
                        .flag("-I/usr/local/cuda/include")
                        .flag("-Isrc/nvidia/NvCodec/include")
                        .flag("-Isrc/nvidia/NvCodec/NvCodec")
                        .file("src/nvidia/NvCodec/NvCodec/NvDecoder/NvDecoder.cpp")
                        .file("src/nvidia/NvCodec/NvCodec/NvEncoder/NvEncoder.cpp")
                        .file("src/nvidia/NvCodec/NvCodec/NvEncoder/NvEncoderCuda.cpp")
                        .file("src/nvidia/h264_encoder_impl.cpp")
                        .file("src/nvidia/h264_decoder_impl.cpp")
                        .file("src/nvidia/nvidia_decoder_factory.cpp")
                        .file("src/nvidia/nvidia_encoder_factory.cpp")
                        .file("src/nvidia/cuda_context.cpp")
                        .file("src/nvidia/implib/libcuda.so.init.c")
                        .file("src/nvidia/implib/libcuda.so.tramp.S")
                        .file("src/nvidia/implib/libnvcuvid.so.init.c")
                        .file("src/nvidia/implib/libnvcuvid.so.tramp.S")
                        .flag("-Wno-deprecated-declarations")
                        .flag("-DUSE_NVIDIA_VIDEO_CODEC=1");

                    #[cfg(feature = "use_x264")]
                    {
                        let (x264_include, x264_lib) = setup_x264();

                        builder
                            .flag("-DWEBRTC_USE_X264=1")
                            .file("src/x264/x264_video_encoder.cpp")
                            .include(&x264_include);

                        let x264_lib_abs =
                            x264_lib.canonicalize().unwrap_or_else(|_| x264_lib.clone());
                        println!("cargo:rustc-link-search=native={}", x264_lib_abs.display());
                        println!("cargo:rustc-link-lib=static=x264");
                    }
                }
                _ => {}
            }

            builder.flag("-Wno-changes-meaning").flag("-std=c++20");
        }
        "macos" => {
            println!("cargo:rustc-link-lib=framework=Foundation");
            println!("cargo:rustc-link-lib=framework=AVFoundation");
            println!("cargo:rustc-link-lib=framework=CoreAudio");
            println!("cargo:rustc-link-lib=framework=AudioToolbox");
            println!("cargo:rustc-link-lib=framework=Appkit");
            println!("cargo:rustc-link-lib=framework=CoreMedia");
            println!("cargo:rustc-link-lib=framework=CoreGraphics");
            println!("cargo:rustc-link-lib=framework=VideoToolbox");
            println!("cargo:rustc-link-lib=framework=CoreVideo");
            println!("cargo:rustc-link-lib=framework=OpenGL");
            println!("cargo:rustc-link-lib=framework=Metal");
            println!("cargo:rustc-link-lib=framework=MetalKit");
            println!("cargo:rustc-link-lib=framework=QuartzCore");
            println!("cargo:rustc-link-lib=framework=IOKit");
            println!("cargo:rustc-link-lib=framework=IOSurface");
            println!("cargo:rustc-link-lib=framework=ScreenCaptureKit");

            configure_darwin_sysroot(&mut builder);

            builder
                .file("src/objc_video_factory.mm")
                .file("src/objc_video_frame_buffer.mm")
                .flag("-stdlib=libc++")
                .flag("-std=c++20");
        }
        "ios" => {
            println!("cargo:rustc-link-lib=framework=Foundation");
            println!("cargo:rustc-link-lib=framework=CoreFoundation");
            println!("cargo:rustc-link-lib=framework=AVFoundation");
            println!("cargo:rustc-link-lib=framework=CoreAudio");
            println!("cargo:rustc-link-lib=framework=UIKit");
            println!("cargo:rustc-link-lib=framework=CoreVideo");
            println!("cargo:rustc-link-lib=framework=CoreGraphics");
            println!("cargo:rustc-link-lib=framework=CoreMedia");
            println!("cargo:rustc-link-lib=framework=VideoToolbox");
            println!("cargo:rustc-link-lib=framework=AudioToolbox");
            println!("cargo:rustc-link-lib=framework=OpenGLES");
            println!("cargo:rustc-link-lib=framework=GLKit");
            println!("cargo:rustc-link-lib=framework=Metal");
            println!("cargo:rustc-link-lib=framework=MetalKit");
            println!("cargo:rustc-link-lib=framework=Network");
            println!("cargo:rustc-link-lib=framework=QuartzCore");

            configure_darwin_sysroot(&mut builder);

            builder
                .file("src/objc_video_factory.mm")
                .file("src/objc_video_frame_buffer.mm")
                .flag("-std=c++20");
        }
        "android" => {
            webrtc_sys_build::configure_jni_symbols().unwrap();

            println!("cargo:rustc-link-lib=EGL");
            println!("cargo:rustc-link-lib=c++abi");
            println!("cargo:rustc-link-lib=OpenSLES");

            configure_android_sysroot(&mut builder);

            #[cfg(feature = "use_x264")]
            {
                let (x264_include, x264_lib) = setup_x264();

                builder
                    .flag("-DWEBRTC_USE_X264=1")
                    .file("src/x264/x264_video_encoder.cpp")
                    .include(&x264_include);

                let x264_lib_abs = x264_lib.canonicalize().unwrap_or_else(|_| x264_lib.clone());
                println!("cargo:rustc-link-search=native={}", x264_lib_abs.display());
                println!("cargo:rustc-link-lib=static=x264");
            }

            builder
                .file("src/android.cpp")
                .file("src/android/video_encoder_factory.cpp")
                .file("src/android/video_decoder_factory.cpp")
                .flag("-std=c++20")
                // Changed from c++_static to c++_shared for Qt compatibility
                .cpp_link_stdlib("c++_shared");
        }
        _ => {
            panic!("Unsupported target, {}", target_os);
        }
    }

    // TODO(theomonnom) Only add this define when building tests
    builder.define("LIVEKIT_TEST", None);
    builder.warnings(false).compile("webrtcsys-cxx");

    for entry in glob::glob("./src/**/*.cpp").unwrap() {
        println!("cargo:rerun-if-changed={}", entry.unwrap().display());
    }

    for entry in glob::glob("./src/**/*.mm").unwrap() {
        println!("cargo:rerun-if-changed={}", entry.unwrap().display());
    }

    for entry in glob::glob("./include/**/*.h").unwrap() {
        println!("cargo:rerun-if-changed={}", entry.unwrap().display());
    }

    // Rebuild if x264 submodule changes
    println!("cargo:rerun-if-changed=third_party/x264");

    if target_os.as_str() == "android" {
        copy_libwebrtc_jar(&PathBuf::from(Path::new(&webrtc_dir)));
    }
}

fn copy_libwebrtc_jar(webrtc_dir: &PathBuf) {
    let jar_path = webrtc_dir.join("libwebrtc.jar");
    let output_path = get_output_path();
    let output_jar_path = output_path.join("libwebrtc.jar");
    let res = std::fs::copy(jar_path, output_jar_path);
    if let Err(e) = res {
        println!("Failed to copy libwebrtc.jar: {}", e);
    }
}

fn get_output_path() -> PathBuf {
    let manifest_dir_string = env::var("CARGO_MANIFEST_DIR").unwrap();
    let build_type = env::var("PROFILE").unwrap();
    let build_target = env::var("TARGET").unwrap();
    let path =
        Path::new(&manifest_dir_string).join("../target").join(build_target).join(build_type);
    return PathBuf::from(path);
}

fn configure_darwin_sysroot(builder: &mut cc::Build) {
    let target_os = webrtc_sys_build::target_os();

    let sdk = match target_os.as_str() {
        "mac" => "macosx",
        "ios-device" => "iphoneos",
        "ios-simulator" => "iphonesimulator",
        _ => panic!("Unsupported target_os: {}", target_os),
    };

    let clang_rt = match target_os.as_str() {
        "mac" => "clang_rt.osx",
        "ios-device" => "clang_rt.ios",
        "ios-simulator" => "clang_rt.iossim",
        _ => panic!("Unsupported target_os: {}", target_os),
    };

    println!("cargo:rustc-link-lib={}", clang_rt);
    println!("cargo:rustc-link-arg=-ObjC");

    let sysroot = Command::new("xcrun").args(["--sdk", sdk, "--show-sdk-path"]).output().unwrap();

    let sysroot = String::from_utf8_lossy(&sysroot.stdout);
    let sysroot = sysroot.trim();

    let search_dirs = Command::new("clang").arg("--print-search-dirs").output().unwrap();

    let search_dirs = String::from_utf8_lossy(&search_dirs.stdout);
    for line in search_dirs.lines() {
        if line.contains("libraries: =") {
            let path = line.split('=').nth(1).unwrap();
            let path = format!("{}/lib/darwin", path);
            println!("cargo:rustc-link-search={}", path);
        }
    }

    builder.flag(format!("-isysroot{}", sysroot).as_str());
}

fn setup_x264() -> (PathBuf, PathBuf) {
    let x264_dir = Path::new("third_party/x264");

    if x264_dir.exists() {
        // Use both headers and library from submodule
        let x264_include = x264_dir.to_path_buf();
        let x264_lib = x264_dir.to_path_buf();

        // Check target architecture to determine the correct library
        let target_os = env::var("CARGO_CFG_TARGET_OS").unwrap();
        let target_arch = env::var("CARGO_CFG_TARGET_ARCH").unwrap();

        let x264_static_lib = match (target_os.as_str(), target_arch.as_str()) {
            ("android", "aarch64") => x264_lib.join("libx264-android-aarch64.a"),
            ("android", "arm") => x264_lib.join("libx264-android-armv7.a"),
            ("linux", "x86_64") => x264_lib.join("libx264.a"),
            _ => x264_lib.join("libx264.a"),
        };

        if !x264_static_lib.exists() {
            println!(
                "cargo:warning=x264 library {:?} not found, building x264 for target {}...",
                x264_static_lib,
                format!("{}-{}", target_os, target_arch)
            );

            // Configure for cross-compilation if building for Android
            if target_os == "android" {
                configure_and_build_x264_android(
                    &x264_dir,
                    &target_arch,
                    &x264_lib,
                    &x264_static_lib,
                );
            } else {
                // Build x264 from source for other targets
                let mut build_cmd = std::process::Command::new("make");
                build_cmd.current_dir(&x264_dir);
                build_cmd.arg("-j").arg(env::var("NUM_JOBS").unwrap_or_else(|_| "4".to_string()));

                let output = build_cmd.output().expect("Failed to build x264");

                if !output.status.success() {
                    panic!("Failed to build x264: {}", String::from_utf8_lossy(&output.stderr));
                }
            }
        }

        println!(
            "cargo:warning=Using x264 submodule headers and library for {}-{}",
            target_os, target_arch
        );
        (x264_include, x264_lib)
    } else {
        panic!("x264 submodule not found at third_party/x264. Please ensure the submodule is initialized and checked out.");
    }
}

fn configure_and_build_x264_android(
    x264_dir: &Path,
    target_arch: &str,
    x264_lib: &PathBuf,
    x264_static_lib: &PathBuf,
) {
    let ndk_home =
        env::var("ANDROID_NDK_HOME").expect("ANDROID_NDK_HOME must be set for Android builds");
    let toolchain_bin = format!("{}/toolchains/llvm/prebuilt/linux-x86_64/bin", ndk_home);

    let (host_triple, cc_name, ar_name, cc_env_var, ar_env_var) = match target_arch {
        "aarch64" => (
            "aarch64-linux-android",
            "aarch64-linux-android28-clang",
            "llvm-ar",
            "CC_aarch64_linux_android",
            "AR_aarch64_linux_android",
        ),
        "arm" => (
            "arm-linux-androideabi",
            "armv7a-linux-androideabi28-clang",
            "llvm-ar",
            "CC_armv7_linux_androideabi",
            "AR_armv7_linux_androideabi",
        ),
        _ => panic!("Unsupported Android architecture: {}", target_arch),
    };

    let cc = env::var(cc_env_var).unwrap_or_else(|_| cc_name.to_string());
    let ar = env::var(ar_env_var).unwrap_or_else(|_| ar_name.to_string());

    // Clean any previous build artifacts
    let _ = std::process::Command::new("make").current_dir(&x264_dir).arg("clean").output();

    // Configure x264 for Android cross-compilation
    let mut configure_cmd = std::process::Command::new("./configure");
    configure_cmd
        .current_dir(&x264_dir)
        .arg(format!("--host={}", host_triple))
        .arg("--enable-static")
        .arg("--disable-cli")
        .arg("--disable-asm") // Disable assembly optimizations to avoid toolchain issues
        .arg("--enable-pic") // Enable position independent code
        .env("CC", &cc)
        .env("AR", &ar)
        .env("PATH", format!("{}:{}", toolchain_bin, env::var("PATH").unwrap_or_default()));

    // Add additional flags for ARMv7
    if target_arch == "arm" {
        configure_cmd
            .arg("--disable-thread") // Disable threading for better compatibility on older ARM devices
            .env("CFLAGS", "-march=armv7-a -mfloat-abi=softfp -mfpu=neon");
    }

    let configure_output = configure_cmd.output().expect("Failed to configure x264 for Android");

    if !configure_output.status.success() {
        println!(
            "cargo:warning=x264 configure stdout: {}",
            String::from_utf8_lossy(&configure_output.stdout)
        );
        println!(
            "cargo:warning=x264 configure stderr: {}",
            String::from_utf8_lossy(&configure_output.stderr)
        );
        panic!(
            "Failed to configure x264 for Android {}: {}",
            target_arch,
            String::from_utf8_lossy(&configure_output.stderr)
        );
    }

    // Build x264
    let mut build_cmd = std::process::Command::new("make");
    build_cmd
        .current_dir(&x264_dir)
        .arg("-j")
        .arg(env::var("NUM_JOBS").unwrap_or_else(|_| "4".to_string()))
        .env("CC", &cc)
        .env("AR", &ar)
        .env("PATH", format!("{}:{}", toolchain_bin, env::var("PATH").unwrap_or_default()));

    let output = build_cmd.output().expect("Failed to build x264");

    if !output.status.success() {
        println!("cargo:warning=x264 build stdout: {}", String::from_utf8_lossy(&output.stdout));
        println!("cargo:warning=x264 build stderr: {}", String::from_utf8_lossy(&output.stderr));
        panic!(
            "Failed to build x264 for Android {}: {}",
            target_arch,
            String::from_utf8_lossy(&output.stderr)
        );
    }

    // Copy the built library to the target-specific name
    let source_lib = x264_lib.join("libx264.a");
    if source_lib.exists() {
        std::fs::copy(&source_lib, &x264_static_lib)
            .expect("Failed to copy x264 library to target-specific name");
        println!(
            "cargo:warning=Successfully built and copied x264 library for Android {}",
            target_arch
        );
    } else {
        panic!("x264 library was not created at expected location: {:?}", source_lib);
    }
}

fn configure_android_sysroot(builder: &mut cc::Build) {
    let toolchain = webrtc_sys_build::android_ndk_toolchain().unwrap();
    let toolchain_lib = toolchain.join("lib");

    let sysroot = toolchain.join("sysroot").canonicalize().unwrap();
    println!("cargo:rustc-link-search={}", toolchain_lib.display());

    builder.flag(format!("-isysroot{}", sysroot.display()).as_str());
}
