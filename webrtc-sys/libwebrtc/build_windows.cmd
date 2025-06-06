@echo on
setlocal enabledelayedexpansion

set arch=
set profile=release

:arg_loop
if "%1" == "" goto end_arg_loop
if "%1" == "--arch" (
    set "arch=%2"
    shift & shift & goto arg_loop
)
if "%1" == "--profile" (
    set "profile=%2"
    shift & shift & goto arg_loop
)
echo Error: Unknown argument '%1'
exit /b 1
:end_arg_loop

if not "!arch!" == "x64" if not "!arch!" == "arm64" (
    echo Error: Invalid value for --arch. Must be 'x64' or 'arm64'.
    exit /b 1
)
if not "!profile!" == "debug" if not "!profile!" == "release" (
    echo Error: Invalid value for --profile. Must be 'debug' or 'release'.
    exit /b 1
)

echo "Building LiveKit WebRTC - Windows"
echo "Arch: !arch!"
echo "Profile: !profile!"

if not exist depot_tools (
  echo "Cloning depot_tools..."
  git clone --depth 1 https://chromium.googlesource.com/chromium/tools/depot_tools.git
)

set COMMAND_DIR=%~dp0
set PATH=%cd%\depot_tools;%PATH%
set DEPOT_TOOLS_WIN_TOOLCHAIN=0
set GYP_GENERATORS=ninja,msvs-ninja
set GYP_MSVS_VERSION=2022
set OUTPUT_DIR=src\out-!arch!-!profile!
set ARTIFACTS_DIR=%cd%\win-!arch!-!profile!
set vs2022_install=C:\Program Files (x86)\Microsoft Visual Studio\2019\Professional

if not exist src (
  echo "Syncing source code with gclient..."
  call gclient.bat sync -D --no-history

)

cd src
@echo on
echo "Applying patches..."
call git apply "%COMMAND_DIR%/patches/add_licenses.patch" -v --ignore-space-change --ignore-whitespace --whitespace=nowarn
call git apply "%COMMAND_DIR%/patches/add_deps.patch" -v --ignore-space-change --ignore-whitespace --whitespace=nowarn
call git apply "%COMMAND_DIR%/patches/windows_silence_warnings.patch" -v --ignore-space-change --ignore-whitespace --whitespace=nowarn
call git apply "%COMMAND_DIR%/patches/ssl_verify_callback_with_native_handle.patch" -v --ignore-space-change --ignore-whitespace --whitespace=nowarn
cd ..

@echo on
echo "Creating artifacts directory..."
mkdir "%ARTIFACTS_DIR%\lib"

set "debug=false"
if "!profile!" == "debug" (
  set "debug=true"
)

@echo on
echo "Generating ninja build files..."
call gn.bat gen %OUTPUT_DIR% --root="src" ^
  --args="is_debug=!debug! is_clang=true target_cpu=\"!arch!\" use_custom_libcxx=false rtc_libvpx_build_vp9=true enable_libaom=true rtc_include_tests=false rtc_build_examples=false rtc_build_tools=false is_component_build=false rtc_enable_protobuf=false rtc_use_h264=true ffmpeg_branding=\"Chrome\" symbol_level=0 enable_iterator_debugging=false"

@echo on
echo "Building with ninja..."
call ninja -C %OUTPUT_DIR% :default

REM Verificar el código de salida de ninja
if errorlevel 1 (
    echo "Error: Ninja build failed with exit code %errorlevel%."
    exit /b %errorlevel%
)

@echo on
echo "Copying static library..."
copy "%OUTPUT_DIR%\obj\webrtc.lib" "%ARTIFACTS_DIR%\lib"

echo "Generating license..."
call python3 "%cd%\src\tools_webrtc\libs\generate_licenses.py" ^
  --target :default %OUTPUT_DIR% %OUTPUT_DIR%

@echo on
echo "Copying additional files..."
copy "%OUTPUT_DIR%\obj\webrtc.ninja" "%ARTIFACTS_DIR%"
copy "%OUTPUT_DIR%\args.gn" "%ARTIFACTS_DIR%"
copy "%OUTPUT_DIR%\LICENSE.md" "%ARTIFACTS_DIR%"

@echo on
echo "Copying headers..."
xcopy src\*.h "%ARTIFACTS_DIR%\include" /C /S /I /F /H

@echo on
echo "Listing artifacts directory contents..."
dir "%ARTIFACTS_DIR%"

