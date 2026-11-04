# Pinned to the head of webrtc-sdk m137_release so builds are reproducible and the
# webrtc_fingerprint.sh Conan key changes with the revision; re-pin when syncing upstream
solutions = [
  {
    "name": 'src',
    "url": 'https://github.com/webrtc-sdk/webrtc.git@a4bd28d99eb9ed3bc8e41ce7b9ce7254ee7308bd',
    "custom_deps": {},
    "deps_file": "DEPS",
    "managed": False,
  },
]
target_os = ["android", "unix"]
