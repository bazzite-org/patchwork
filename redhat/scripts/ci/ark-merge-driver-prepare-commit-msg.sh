#!/bin/bash

# Git prepare-commit-msg hook to add AI resolution information
# Install this hook by copying it to .git/hooks/prepare-commit-msg and making it executable

COMMIT_MSG_FILE="$1"
COMMIT_SOURCE="$2"
#SHA1="$3" # Not used

# Simple file to track AI resolutions
AI_RESOLUTIONS_FILE="/tmp/ark-md-ai-resolutions"

# Add AI info for merge commits
if [[ "$COMMIT_SOURCE" == "merge" ]]; then
    if [[ -f "$AI_RESOLUTIONS_FILE" && -s "$AI_RESOLUTIONS_FILE" ]]; then
        echo -e "\n\nAI-assisted merge conflict resolution.\nFiles resolved:" >> "$COMMIT_MSG_FILE"

        # Sort and deduplicate the file list, then add to commit message
        sort -u "$AI_RESOLUTIONS_FILE" | while read -r file_path; do
            echo "  - $file_path" >> "$COMMIT_MSG_FILE"
        done

        echo "" >> "$COMMIT_MSG_FILE"
        
        # Clean up the resolutions file after use
        rm -f "$AI_RESOLUTIONS_FILE"
    fi
fi
