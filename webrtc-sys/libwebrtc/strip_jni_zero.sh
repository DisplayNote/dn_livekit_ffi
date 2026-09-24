#!/bin/bash

set -e

OUTPUT_DIR="${OUTPUT_DIR:-$1}"

# org.jni_zero is the only WebRTC package migrate_webrtc.sh does NOT rename to
# livekit.org.webrtc, so this jar and the host application's own libwebrtc.jar
# would otherwise define the same classes twice and D8 would refuse to dex the
# APK. We therefore drop the copies the host already provides.
#
# Two classes must survive that cull. They are the jni_zero bootstrap this
# library's native code looks up by name (liblivekit_ffi.so is the only binary
# in the APK that references org/jni_zero/JniInit), and WebRTC deleted them
# upstream somewhere between M138 and M153. A host on a modern WebRTC no longer
# ships them, so stripping them here leaves nobody to provide them and the
# broadcast process dies with ClassNotFoundException the moment it starts.
# Nothing detects that at build time -- hence the hard failure below.
# Fix: https://dev.azure.com/displaynote-devops/Montage/_workitems/edit/141676
KEEP_CLASSES=(JniInit JniUtil)

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

# Fail loudly if a class we must keep is gone: that means the WebRTC revision
# in .gclient moved past the point where jni_zero still defines it, and the
# assumption this whole script rests on no longer holds. Better a broken build
# than a jar that dexes cleanly and crashes on device.
#
# Checked before -- and independently of -- the directory test below, because
# a revision that drops org/jni_zero altogether would otherwise skip the whole
# block, guard included, and emit a jar missing the bootstrap without a word.
for cls in "${KEEP_CLASSES[@]}"; do
  if ! compgen -G "org/jni_zero/${cls}.class" >/dev/null; then
    echo "Error: org/jni_zero/${cls}.class is not in this libwebrtc.jar." >&2
    echo "       liblivekit_ffi.so resolves it at runtime, so the APK would" >&2
    echo "       build and then crash on the first broadcast. Check whether" >&2
    echo "       the WebRTC revision in .gclient still provides it." >&2
    exit 1
  fi
done

# Remove org.jni_zero classes, except the bootstrap ones listed above. The
# directory necessarily exists at this point -- the check above found classes
# inside it -- so this test is belt and braces, not the gate.
if [[ -d "org/jni_zero" ]]; then
  echo "  Removing org/jni_zero classes except: ${KEEP_CLASSES[*]}"
  keep_expr=()
  for cls in "${KEEP_CLASSES[@]}"; do
    # Also keeps nested classes, e.g. JniInit$1.class
    keep_expr+=( ! -name "${cls}.class" ! -name "${cls}\$*.class" )
  done
  find "org/jni_zero" -type f "${keep_expr[@]}" -delete
  # Drop directories the cull left empty.
  find "org/jni_zero" -type d -empty -delete

  echo "  Kept: $(find org/jni_zero -name '*.class' 2>/dev/null | sort | tr '\n' ' ')"
fi

# Recreate the JAR
jar -cf "$OUTPUT_DIR/lib.java/sdk/android/libwebrtc.jar" .

popd >/dev/null
rm -rf "$temp_jar_dir"
echo "  ✓ Stripped org.jni_zero symbols from libwebrtc.jar"
