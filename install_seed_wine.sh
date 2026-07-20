#!/bin/bash
#####################################################################################
# Author: Tempus Thales
# Version: 0.01
# Date: 07/19/2026
# Description: Bootstrap a Wine prefix for .NET era Windows applications.
#
# Creates (or updates) a 64-bit Wine prefix, sets the reported Windows version to
# Windows 10, then installs .NET Framework 4.5.2 and the Microsoft core fonts.
# Optionally launches an executable inside the prepared prefix.
#
# Credit: Based on the original script shared by King Peky.
# Source: https://discord.com/channels/284733225753116682/1351162032031924294/1447186146978168852
# Note: Join SEED discord here first, then use the link above: https://discord.gg/seedgame
#####################################################################################
# Changelog:
#
# 0.01 - 07/19/2026 - Initial version
#                   - Credit to King Peky for the original script
#                   - Added dependency checks for wine, wineboot, wineserver, winetricks
#                   - Added error trapping on every stage with descriptive messages
#                   - Prefix path is resolved to an absolute path before use
#                   - Existing prefix architecture is validated before touching it
#                   - Added -h and /? usage output
#####################################################################################

set -o pipefail

SCRIPT_NAME="$(basename "$0")"

usage() {
    cat <<EOF
Usage: $SCRIPT_NAME <wineprefix_path> [executable_path]

Bootstrap a 64-bit Wine prefix with Windows 10 compatibility, .NET Framework
4.5.2, and the Microsoft core fonts.

Arguments:
  wineprefix_path   Path to the Wine prefix. Created if it does not exist.
  executable_path   Optional. Windows executable to run once setup finishes.

Options:
  -h, --help, /?    Show this help and exit.

Examples:
  $SCRIPT_NAME ~/.wine_custom
  $SCRIPT_NAME ~/.wine_custom /path/to/program.exe
EOF
}

die() {
    echo "Error: $*" >&2
    exit 1
}

# ---- Argument handling ------------------------------------------------------

case "$1" in
    -h|--help|/\?|"")
        usage
        [ -z "$1" ] && exit 1
        exit 0
        ;;
esac

PREFIX_ARG="$1"
EXECUTABLE="$2"

# ---- Dependency checks ------------------------------------------------------

for cmd in wine wineboot wineserver winetricks; do
    command -v "$cmd" >/dev/null 2>&1 || die "'$cmd' not found on PATH. Install wine and winetricks first."
done

# ---- Resolve prefix to an absolute path -------------------------------------
# Wine rejects relative WINEPREFIX values. realpath -m works whether or not the
# directory already exists.

WINEPREFIX="$(realpath -m "$PREFIX_ARG")" || die "Could not resolve prefix path: $PREFIX_ARG"

export WINEPREFIX
export WINEARCH=win64

# ---- Validate an existing prefix --------------------------------------------
# WINEARCH only applies at creation time. Pointing win64 at an existing 32-bit
# prefix makes wine bail with a confusing error, so catch it here instead.

if [ -f "$WINEPREFIX/system.reg" ]; then
    if grep -q '#arch=win32' "$WINEPREFIX/system.reg"; then
        die "$WINEPREFIX is an existing 32-bit prefix. This script builds win64 prefixes. Use a different path or remove the old prefix."
    fi
    echo "Existing 64-bit prefix found at: $WINEPREFIX"
else
    echo "Creating new Wine prefix at: $WINEPREFIX"
fi

# ---- Initialize the prefix --------------------------------------------------

echo "Running wineboot..."
wineboot -u || die "wineboot failed. The prefix may be in an inconsistent state."

echo "Waiting for prefix initialization to settle..."
wineserver -w || die "wineserver -w returned an error while waiting for wineboot."

# ---- Configure -------------------------------------------------------------

echo "Setting Windows version to Windows 10..."
winetricks -q win10 || die "Failed to set the Windows version to win10."

echo "Installing .NET Framework 4.5.2 (this takes a while)..."
winetricks -q --force dotnet452 || die "Failed to install .NET Framework 4.5.2."

echo "Installing Microsoft core fonts..."
winetricks -q corefonts || die "Failed to install corefonts."

echo ""
echo "Wine prefix initialization complete."
echo "  Prefix location: $WINEPREFIX"
echo "  Architecture:    win64"
echo "  Windows version: Windows 10"
echo "  Installed:       .NET Framework 4.5.2, Core Fonts"

# ---- Optionally run the executable ------------------------------------------

if [ -n "$EXECUTABLE" ]; then
    [ -f "$EXECUTABLE" ] || die "Executable not found: $EXECUTABLE"
    [ -r "$EXECUTABLE" ] || die "Executable is not readable: $EXECUTABLE"

    echo ""
    echo "Running: $EXECUTABLE"
    wine "$EXECUTABLE"
    exit $?
fi

exit 0