#!/usr/bin/env bash
# LiveKit WebRTC Package Migration Script
# Migrates org.webrtc -> livekit.org.webrtc across WebRTC sources

set -euo pipefail

# migrate_webrtc function - migrates org.webrtc references to livekit.org.webrtc
migrate_webrtc() {
  local root="$1"
  if [[ ! -d "$root" ]]; then
    echo "migrate_webrtc: '$root' is not a directory" >&2
    return 1
  fi
  echo "Running migrate_webrtc in: $root"

  # WebRTC-related folders to process (avoids unnecessary processing of unrelated code)
  local webrtc_folders=(
    "sdk"
    "api" 
    "modules/audio_device/android"
    "modules/audio_coding/audio_network_adaptor"
    "modules/video_capture/android"
    "modules/video_coding/codecs/h264/android"
    "modules/video_coding/codecs/vp8/android"
    "modules/video_coding/codecs/vp9/android"
    "rtc_base"
    "examples/android*"
    "test/android"    
  )

  # File types to process
  local exts=(
    "*.java" "*.kt" "*.xml" "*.gn" "*.gni" "*.proto"
    "*.c" "*.cc" "*.cpp" "*.cxx" "*.hpp" "*.hh" "*.h" "*.hxx"
    "*.m" "*.mm" "*.gradle" "*.properties" "*.mk" "*.cmake"
  )

  local find_expr=()
  for i in "${!exts[@]}"; do
    if [[ $i -gt 0 ]]; then find_expr+=(-o); fi
    find_expr+=(-name "${exts[$i]}")
  done

  local changed=0
  local total_files=0

  # Helper function to process a single folder
  process_folder() {
    local folder_path="$1"
    local folder_files=0
    
    echo "    Starting to process folder: $folder_path"
    
    # Check if folder exists and is accessible
    if [[ ! -d "$folder_path" ]]; then
      echo "    Error: Folder does not exist: $folder_path"
      return 1
    fi
    
    # Create find command and test it first
    local find_cmd="find \"$folder_path\" -type f \\( ${find_expr[*]} \\) -print0 2>/dev/null"
    echo "    Find command: $find_cmd"
    
    # Use safer approach without process substitution
    local temp_list
    temp_list="$(mktemp)"
    
    if ! find "$folder_path" -type f \( "${find_expr[@]}" \) -print0 2>/dev/null > "$temp_list"; then
      echo "    Warning: Find command failed for $folder_path"
      rm -f "$temp_list"
      return 0
    fi
    
    # Process files from the temp list
    while IFS= read -r -d '' file; do
      if [[ -z "$file" ]]; then
        continue
      fi
      
      local tmp
      tmp="$(mktemp)"
      if ! cp "$file" "$tmp" 2>/dev/null; then
        echo "    Warning: Failed to copy $file, skipping"
        rm -f "$tmp"
        continue
      fi
      
      ((total_files++))
      ((folder_files++))

      # Dot-notation and slash-notation replacements with double-prefix protection
      if ! perl -0777 -i -pe '
        s/(?<!livekit\.)\borg\.webrtc\b/livekit.org.webrtc/g;
        s{(?<!livekit/)org/webrtc\b}{livekit/org/webrtc}g;
        s{L(?<!livekit/)org/webrtc/}{Llivekit/org/webrtc/}g;
        s/package="org\.webrtc"/package="livekit.org.webrtc"/g;
        s/android:name="org\.webrtc"/android:name="livekit.org.webrtc"/g;
        s/(?<!livekit_)org_webrtc(?!_)/livekit_org_webrtc/g;
        s/(?<!livekit_)org_webrtc_/livekit_org_webrtc_/g;
        s/Java_(?<!livekit_)org_webrtc_/Java_livekit_org_webrtc_/g;
        s/_(?<!livekit_)org_webrtc_/_livekit_org_webrtc_/g;
        s/(?<!livekit_)org_webrtc_([A-Za-z0-9_]+)_clazz/livekit_org_webrtc_$1_clazz/g;
      ' "$file" 2>/dev/null; then
        echo "    Warning: Failed to process $file with perl, skipping"
        rm -f "$tmp"
        continue
      fi
      

      if ! cmp -s "$file" "$tmp" 2>/dev/null; then
        echo "    updated: $file"
        ((changed++))
      fi
      rm -f "$tmp"
    done < "$temp_list"
    
    rm -f "$temp_list"
    echo "    processed $folder_files files in $(basename "$folder_path")"
    return 0
  }

  # Process each WebRTC-related folder
  for folder in "${webrtc_folders[@]}"; do
    echo "  Checking folder: $folder"
    
    # Handle wildcard patterns by expanding them
    if [[ "$folder" == *"*"* ]]; then
      echo "    Expanding wildcard pattern: $folder"
      # Use shell globbing for wildcard patterns
      local found_folders=()
      if pushd "$root" >/dev/null 2>&1; then
        shopt -s nullglob  # Enable nullglob to handle no matches
        for expanded_folder in $folder; do
          if [[ -d "$expanded_folder" ]]; then
            found_folders+=("$expanded_folder")
            echo "    Found: $expanded_folder"
          fi
        done
        shopt -u nullglob  # Disable nullglob
        popd >/dev/null 2>&1
      else
        echo "    Warning: Failed to change to directory $root"
        continue
      fi
      
      # Process each expanded folder
      if [[ ${#found_folders[@]} -eq 0 ]]; then
        echo "    No folders found matching pattern: $folder"
      else
        for expanded_folder in "${found_folders[@]}"; do
          local folder_path="$root/$expanded_folder"
          echo "  Processing folder: $expanded_folder"
          if ! process_folder "$folder_path"; then
            echo "    Warning: Failed to process folder $expanded_folder"
          fi
        done
      fi
    else
      # Handle regular folder paths
      local folder_path="$root/$folder"
      if [[ -d "$folder_path" ]]; then
        echo "  Processing folder: $folder"
        if ! process_folder "$folder_path"; then
          echo "    Warning: Failed to process folder $folder"
        fi
      else
        echo "  Skipping non-existent folder: $folder"
      fi
    fi
  done

  echo "migrate_webrtc: processed $total_files files, updated $changed files"
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <webrtc_source_directory>" >&2
    echo "Example: $0 \$(pwd)/src" >&2
    exit 1
  fi
  
  migrate_webrtc "$1"
fi