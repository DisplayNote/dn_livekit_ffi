from conans import ConanFile, CMake, tools


class LivekitFfiConan(ConanFile):
    name = "livekit-ffi"
    version = "0.7.2"
    license = "None"
    author = "jfjalburquerque"
    url = "None"
    description = "Livekit ffi package"
    settings = "os", "compiler", "build_type", "arch"
    options = {"shared": [True, False], "fPIC": [True, False]}
    default_options = {"shared": False, "fPIC": True}
    generators = "cmake"

    def getEnvs(self):
        pass

    def package_info(self):
      self.cpp_info.includedirs = ["include"]

      if self.settings.os == 'Android':
          if self.settings.arch == 'armv7':
              self.cpp_info.libdirs = ["lib/armeabi-v7a"]
          elif self.settings.arch == 'armv8':
              self.cpp_info.libdirs = ["lib/arm64-v8a"]
      elif self.settings.os == "Windows":
          self.cpp_info.libdirs = ["lib"]
      else:
          self.cpp_info.libdirs = ["lib"]

      self.cpp_info.libs = tools.collect_libs(self)

    def package(self):
        self.copy("*", dst="include", src="include")

        if self.settings.os == "Android":
            if self.settings.arch == "armv8":
                lib_folder = "lib/android/arm64-v8a"
                dst_lib_folder = "lib/arm64-v8a"
            elif self.settings.arch == "armv7":
                lib_folder = "lib/android/armeabi-v7a"
                dst_lib_folder = "lib/armeabi-v7a"

            self.copy("*.a", dst=dst_lib_folder, src=lib_folder, keep_path=False)
            self.copy("*.so", dst=dst_lib_folder, src=lib_folder, keep_path=False)
            self.copy("*.jar", dst=dst_lib_folder, src=lib_folder, keep_path=False)

        if self.settings.os == "Windows":
            lib_folder = "lib/windows"
            dst_lib_folder = "lib"
            self.copy("*.lib", dst=dst_lib_folder, src=lib_folder, keep_path=False)
            self.copy("*.dll", dst=dst_lib_folder, src=lib_folder, keep_path=False)
        else:
            self.copy("*.a", dst="lib", src="lib", keep_path=False)
            self.copy("*.so", dst="lib", src="lib", keep_path=False)
            self.copy("*.dylib", dst="lib", src="lib", keep_path=False)
            self.copy("*.lib", dst="lib", src="lib", keep_path=False)
            self.copy("*.dll", dst="bin", src="bin", keep_path=False)


        self.copy("LICENSE", dst="licenses", src=".")


    # REQ VIA QMAKE,
    #def requirements(self):
    #    qt_exact_requirements(self)

    def imports(self):
        dest = os.getenv("CONAN_IMPORT_DEST_PATH", "bin")
        self.copy("*", dst=dest, src="lib")
        self.copy("*", dst="lib", src="lib")
        self.copy("*", dst="include", src="include")
        self.copy("*.qch", dst="doc", src="doc")

    def build(self):
        pass
