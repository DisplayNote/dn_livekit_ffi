import os
import re

from conans import ConanFile


class WebrtcConan(ConanFile):
    """Prebuilt libwebrtc for livekit-ffi (webrtc-sdk m137 + DN patches + livekit.org.webrtc rename).

    Same package conventions as the other DN webrtc/<milestone> packages (export-pkg only,
    os/compiler/build_type/arch settings) but published on the dn/livekit channel: it is not
    ABI-compatible with the dnrtc WebRTC builds. The package keeps the LiveKit artifact layout
    (include/, lib/, webrtc.ninja, args.gn, LICENSE.md, libwebrtc.jar) produced by
    build_<os> so it can be used directly as LK_CUSTOM_WEBRTC.

    Created from a build folder, never built by Conan:
        conan export-pkg conan/conanfile.py <ref from webrtc_fingerprint.sh> \
            -pr <profile>.release --package-folder <os>-<arch>-release -f
    """

    name = 'webrtc'
    settings = 'os', 'compiler', 'build_type', 'arch'
    description = 'libwebrtc prebuilt for livekit-ffi'
    url = 'https://github.com/DisplayNote/dn_livekit_ffi'
    license = 'BSD-3-Clause'
    short_paths = True

    # Same filter as webrtc-sys-build IGNORE_DEFINES
    _ignore_defines = {'CR_CLANG_REVISION', 'CR_XCODE_VERSION'}

    def package_info(self):
        self.cpp_info.includedirs = ['include', 'include/third_party/abseil-cpp']
        self.cpp_info.libdirs = ['lib']
        self.cpp_info.libs = ['webrtc']
        self.cpp_info.defines = self._webrtc_defines()

        if self.settings.os == 'Windows':
            self.cpp_info.system_libs = ['msdmo', 'wmcodecdspuuid', 'dmoguids', 'crypt32', 'iphlpapi',
                                         'ole32', 'secur32', 'winmm', 'ws2_32', 'strmiids', 'd3d11',
                                         'gdi32', 'dxgi', 'dwmapi', 'shcore']
        elif self.settings.os == 'Android':
            self.cpp_info.system_libs = ['EGL', 'OpenSLES', 'c++abi']

        # webrtc-sys/build reads this layout as-is
        self.user_info.LK_CUSTOM_WEBRTC = self.package_folder

    def _webrtc_defines(self):
        ninja = os.path.join(self.package_folder, 'webrtc.ninja')
        if not os.path.isfile(ninja):
            return []
        with open(ninja) as f:
            first_line = f.readline()
        defines = []
        for name, value in re.findall(r'-D(\w+)(?:=([^\s]+))?', first_line):
            if name in self._ignore_defines:
                continue
            defines.append('{}={}'.format(name, value) if value else name)
        return defines
