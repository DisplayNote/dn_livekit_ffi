#!/bin/bash
# Prints the Conan reference of the prebuilt libwebrtc for <target_os> <arch> <profile>.
# The version embeds a hash of every input that changes the build output: the pinned WebRTC
# revision (.gclient), the DN build scripts and patches, the Conan recipe and the build params,
# so CI only rebuilds WebRTC when one of them changes. Bump SALT to force a rebuild.
#
#   ./webrtc_fingerprint.sh android arm64 release   ->  webrtc/137.<hash12>@dn/livekit
#
# With --azure-var <name> it also sets that Azure Pipelines variable to the reference.

set -euo pipefail

SALT="dn-webrtc-v1"
MILESTONE="137"
CHANNEL="dn/livekit"

azure_var=""
if [ "${1:-}" = "--azure-var" ]; then
  azure_var="$2"
  shift 2
fi

if [ $# -ne 3 ]; then
  echo "Usage: $0 [--azure-var <name>] <target_os> <arch> <profile>" >&2
  exit 1
fi
target_os="$1"
arch="$2"
profile="$3"

cd "$(dirname "${BASH_SOURCE[0]}")"

build_script="build_${target_os}.sh"
if [ "$target_os" = "win" ]; then
  build_script="build_windows.cmd"
fi
if [ ! -f "$build_script" ]; then
  echo "Unknown target_os '$target_os' (no $build_script)" >&2
  exit 1
fi

inputs=(.gclient "$build_script" migrate_webrtc.sh webrtc_structure.sh strip_jni_zero.sh
  boringssl_prefix_symbols.txt conan/conanfile.py)
while IFS= read -r patch; do
  inputs+=("$patch")
done < <(find patches -type f | LC_ALL=C sort)

# CRs are stripped so a Windows checkout (core.autocrlf) hashes the same as a Linux one
hash=$(
  {
    printf '%s\n' "$SALT" "$target_os" "$arch" "$profile"
    for f in "${inputs[@]}"; do
      printf '== %s\n' "$f"
      tr -d '\r' < "$f"
    done
  } | sha256sum | cut -c1-12
)

ref="webrtc/${MILESTONE}.${hash}@${CHANNEL}"
echo "$ref"
if [ -n "$azure_var" ]; then
  echo "##vso[task.setvariable variable=${azure_var}]${ref}"
fi
