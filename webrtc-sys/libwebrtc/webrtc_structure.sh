#!/usr/bin/env bash
# LiveKit WebRTC Package Structure Creation Script
# Creates new package directory structure for migrated files

set -euo pipefail

# create_package_structure function - creates new livekit/org/webrtc directory structure
create_package_structure() {
  local src_dir="$1"
  
  if [[ ! -d "$src_dir" ]]; then
    echo "create_package_structure: '$src_dir' is not a directory" >&2
    return 1
  fi
  
  echo "Creating new package directory structure in: $src_dir"
  
  pushd "$src_dir" >/dev/null

  # Find all directories containing org/webrtc structure, excluding out* folders
  find . -type d -path "*/org/webrtc" -not -path "./out*" -not -path "*/out*" | while read -r webrtc_dir; do
    # Get the parent directory (e.g., ./sdk/android/src/java)
    parent_dir=$(dirname "$(dirname "$webrtc_dir")")
    
    # Check if we already have a livekit directory in this parent - if so, skip to avoid duplicates
    if [[ -d "$parent_dir/livekit" ]]; then
      echo "  Skipping $webrtc_dir - livekit directory already exists in $parent_dir"
      continue
    fi
    
    # Create the new livekit/org/webrtc structure
    new_dir="$parent_dir/livekit/org/webrtc"
    echo "  Creating directory: $new_dir"
    mkdir -p "$new_dir"
    
    # Move all files and subdirectories from org/webrtc to livekit/org/webrtc
    if [[ -d "$webrtc_dir" ]]; then
      echo "  Moving contents from $webrtc_dir to $new_dir"
      mv "$webrtc_dir"/* "$new_dir/" 2>/dev/null || true
      
      # Remove the now-empty org/webrtc directory
      rmdir "$webrtc_dir" 2>/dev/null || true
      
      # Clean up empty parent directories if they exist
      org_dir=$(dirname "$webrtc_dir")
      if [[ -d "$org_dir" && -z "$(ls -A "$org_dir" 2>/dev/null)" ]]; then
        rmdir "$org_dir" 2>/dev/null || true
      fi
    fi
  done

  popd >/dev/null
  echo "Package structure creation complete."
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <source_directory>" >&2
    echo "Example: $0 src" >&2
    exit 1
  fi
  
  create_package_structure "$1"
fi