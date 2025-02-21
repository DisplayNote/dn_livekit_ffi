@echo off
setlocal enabledelayedexpansion

echo Script started with arguments: %*

:: Verificar si hay argumentos
if "%~1"=="" (
    echo Error: No arguments provided.
    goto :usage
)

:: Manejo de argumentos
set "platform="
if /i "%~1"=="--platform" (
    if "%~2"=="" (
        echo Error: No platform specified.
        goto :usage
    )
    set "platform=%~2"
) else (
    echo Error: Invalid argument %~1
    goto :usage
)

echo Selected platform: %platform%

:: Guardar el directorio actual
set "initial_path=%CD%"
cd /d "%~dp0"

:: Llamar a la función de compilación según la plataforma
if /i "%platform%"=="windows" (
    call :build_windows
) else if /i "%platform%"=="android" (
    call :build_android
) else (
    echo Error: Invalid platform %platform%.
    goto :usage
)

:: Volver al directorio inicial
cd /d "%initial_path%"
exit /b 0

:: Función de ayuda
:usage
echo Usage: %~nx0 --platform ^<windows^|android^>
echo Example: %~nx0 --platform windows
exit /b 1

:: Función para compilar en Windows
:build_windows
echo Building for Windows...
cargo clean
cargo build --release --target x86_64-pc-windows-msvc
call :create_folder_structure "x86_64-pc-windows-msvc"
exit /b 0

:: Función para compilar en Android
:build_android
echo Building for Android...
if not defined ANDROID_NDK_HOME (
    echo Error: ANDROID_NDK_HOME is not set. Please set it before running the script.
    exit /b 1
)

:: Build armv8 (arm64)
cargo clean
cargo ndk --bindgen --target aarch64-linux-android build --release --no-default-features --features "rustls-tls-webpki-roots"
call :create_folder_structure "aarch64-linux-android"

:: Build armv7 (32-bit)
cargo clean
cargo ndk --bindgen --target armv7-linux-androideabi build --release --no-default-features --features "rustls-tls-webpki-roots"
call :create_folder_structure "armv7-linux-androideabi"
exit /b 0

:: Función para crear la estructura de carpetas
:create_folder_structure
set "target=%~1"

if "%target%"=="" (
    echo Error: Target not specified.
    exit /b 1
)

set "conan_dir=..\livekit-ffi_conan"
if not exist "%conan_dir%\lib" mkdir "%conan_dir%\lib"
if not exist "%conan_dir%\include" mkdir "%conan_dir%\include"

set "conan_assets_path=%~dp0conan_assets"
copy "%conan_assets_path%\conanfile.py" "%conan_dir%\conanfile.py" >nul

if "%target%"=="x86_64-pc-windows-msvc" (
    if not exist "%conan_dir%\lib\windows" mkdir "%conan_dir%\lib\windows"
    copy "..\target\%target%\release\livekit_ffi.dll" "%conan_dir%\lib\windows\" >nul
    copy "..\target\%target%\release\livekit_ffi.dll.lib" "%conan_dir%\lib\windows\livekit_ffi.lib" >nul
) else if "%target%"=="aarch64-linux-android" (
    if not exist "%conan_dir%\lib\android\arm64-v8a" mkdir "%conan_dir%\lib\android\arm64-v8a"
    copy "..\target\%target%\release\liblivekit_ffi.so" "%conan_dir%\lib\android\arm64-v8a\" >nul
    copy "..\target\%target%\release\libwebrtc.jar" "%conan_dir%\lib\android\arm64-v8a\" >nul
) else if "%target%"=="armv7-linux-androideabi" (
    if not exist "%conan_dir%\lib\android\armeabi-v7a" mkdir "%conan_dir%\lib\android\armeabi-v7a"
    copy "..\target\%target%\release\liblivekit_ffi.so" "%conan_dir%\lib\android\armeabi-v7a\" >nul
    copy "..\target\%target%\release\libwebrtc.jar" "%conan_dir%\lib\android\armeabi-v7a\" >nul
) else (
    echo Error: Unrecognized target: %target%
    exit /b 1
)

copy "%~dp0include\livekit_ffi.h" "%conan_dir%\include\" >nul

echo Folder structure created and files copied successfully for %target%.
exit /b 0
