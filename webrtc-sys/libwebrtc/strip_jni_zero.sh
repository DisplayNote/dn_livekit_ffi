#!/bin/bash

set -e

OUTPUT_DIR="${OUTPUT_DIR:-$1}"

if [[ -z "$OUTPUT_DIR" ]]; then
    echo "Error: OUTPUT_DIR not set and no argument provided"
    echo "Usage: $0 <output_dir>"
    exit 1
fi

if [[ ! -f "$OUTPUT_DIR/lib.java/sdk/android/libwebrtc.jar" ]]; then
    echo "Error: libwebrtc.jar not found at $OUTPUT_DIR/lib.java/sdk/android/libwebrtc.jar"
    exit 1
fi

echo "Stripping org.jni_zero symbols from libwebrtc.jar..."
temp_jar_dir="$(mktemp -d)"
pushd "$temp_jar_dir" >/dev/null

# Extract the JAR
jar -xf "$OUTPUT_DIR/lib.java/sdk/android/libwebrtc.jar"

# Remove org.jni_zero classes
if [[ -d "org/jni_zero" ]]; then
  echo "  Removing org/jni_zero directory..."
  rm -rf "org/jni_zero"
fi

# Recreate the JAR without org.jni_zero
jar -cf "$OUTPUT_DIR/lib.java/sdk/android/libwebrtc.jar" .

popd >/dev/null
rm -rf "$temp_jar_dir"
echo "  ✓ Stripped org.jni_zero symbols from libwebrtc.jar"