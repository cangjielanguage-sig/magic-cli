#!/bin/bash

# Get the absolute path of the script's directory (resolves symlinks)
SCRIPT_DIR=$(dirname "$(realpath "$0" 2>/dev/null || readlink -f "$0" 2>/dev/null || echo "$0")")

# Set the library path to "../target" relative to the script's location
CLI_LIB_PATH="$SCRIPT_DIR/../target/release/cli"
MAGIC_LIB_PATH="$SCRIPT_DIR/../target/release/magic"
STDX_LIB_PATH=$(find "${MAGIC_PATH:-}" -type d -path '*/dynamic/stdx' -print -quit 2>/dev/null)

LIB_PATHS="$CLI_LIB_PATH:$MAGIC_LIB_PATH:$STDX_LIB_PATH"

# Path to the executable CLI binary ("../target/bin/cli" relative to the script)
CLI_BIN="$SCRIPT_DIR/../target/release/bin/cli"
# Check if the executable exists before running
if [[ ! -f "$CLI_BIN" ]]; then
    echo "Error: Executable not found at $CLI_BIN" >&2
    exit 1
fi

# Add the library path to `LD_LIBRARY_PATH` (for Linux) and `DYLD_LIBRARY_PATH` (for macOS)
. $CANGJIE_HOME/envsetup.sh
export LD_LIBRARY_PATH="$LIB_PATHS:$LD_LIBRARY_PATH"
export DYLD_LIBRARY_PATH="$LIB_PATHS:$DYLD_LIBRARY_PATH"  # macOS support

# xattr -dr com.apple.quarantine ${script_dir}/* &> /dev/null || true
codesign -s - -f --preserve-metadata=entitlements,requirements,flags,runtime $CLI_BIN &> /dev/null || true

# Execute the CLI binary and forward all arguments (`$@`)
exec "$CLI_BIN" "$@"
