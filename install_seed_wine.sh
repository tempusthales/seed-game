#!/bin/bash
#####################################################################################
# Author: Tempus Thales
# Version: 0.03
# Date: 07/21/2026
# Description: Install and run seed.game on Linux under Wine.
#
# Builds a 64-bit Wine prefix, reports Windows 10, installs .NET Framework 4.5.2
# and the Microsoft core fonts, then downloads and runs the official Windows
# installer inside the prepared prefix.
#
# There is no native Linux build of seed.game. This script runs the Windows
# installer under Wine instead.
#
# Credit: Based on the original script shared by King Peky.
# Source: https://discord.com/channels/284733225753116682/1351162032031924294/1447186146978168852
#####################################################################################
# Changelog:
#
# 0.03 - 07/21/2026 - Searches for an existing seed-launcher.exe before downloading
#                   - Added -f to force a fresh download
#                   - Discovery validates the MZ header, so a truncated or stale
#                     file is ignored rather than used
#                   - Download target renamed to seed-launcher.exe
#
# 0.02 - 07/20/2026 - Downloads the official Windows installer automatically when
#                     no installer path is supplied
#                   - Added -u to override the download URL
#                   - Added -k to keep the downloaded installer instead of
#                     discarding it
#                   - Downloaded file is checked for the MZ header so an error
#                     page never reaches wine
#                   - Switched to getopts for option handling
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

# Version-agnostic endpoint. Always serves the current stable Windows x64 build,
# so there is no version string to maintain here.
SEED_URL="https://launcher.seed.game/latest/stable/win/x64"

# Filename the launcher is distributed as. Used for local discovery.
INSTALLER_NAME="seed-launcher.exe"

KEEP_INSTALLER=0
FORCE_DOWNLOAD=0
TMP_DIR=""

usage() {
    cat <<EOF
Usage: $SCRIPT_NAME [options] <wineprefix_path> [installer_path]

Install seed.game under Wine. Builds a 64-bit prefix with Windows 10
compatibility, .NET Framework 4.5.2, and the Microsoft core fonts, then runs
the installer inside it.

With no installer_path, an existing seed-launcher.exe is located on disk.
If none is found, the official launcher is downloaded automatically.

Arguments:
  wineprefix_path   Path to the Wine prefix. Created if it does not exist.
  installer_path    Optional. Use a local installer instead of downloading.

Options:
  -u <url>          Override the installer download URL.
                    Default: $SEED_URL
  -k                Keep the downloaded installer in the prefix directory
                    instead of discarding it after the run.
  -f                Force a fresh download, ignoring any local copy.
  -h, --help, /?    Show this help and exit.

Examples:
  $SCRIPT_NAME ~/.seed-game
  $SCRIPT_NAME -k ~/.seed-game
  $SCRIPT_NAME ~/.seed-game ~/Downloads/seed-setup.exe
EOF
}

die() {
    echo "Error: $*" >&2
    exit 1
}

# shellcheck disable=SC2317  # invoked via trap
cleanup() {
    if [ -n "$TMP_DIR" ] && [ -d "$TMP_DIR" ]; then
        rm -rf "$TMP_DIR"
    fi
}
trap cleanup EXIT

# ---- Option parsing ---------------------------------------------------------

case "$1" in
    --help|/\?|"")
        usage
        [ -z "$1" ] && exit 1
        exit 0
        ;;
esac

while getopts ":u:kfh" opt; do
    case "$opt" in
        u) SEED_URL="$OPTARG" ;;
        k) KEEP_INSTALLER=1 ;;
        f) FORCE_DOWNLOAD=1 ;;
        h) usage; exit 0 ;;
        :) die "Option -$OPTARG requires an argument." ;;
        \?) die "Unknown option: -$OPTARG. Use -h for help." ;;
    esac
done
shift $((OPTIND - 1))

[ -n "$1" ] || { usage; exit 1; }

PREFIX_ARG="$1"
INSTALLER="$2"

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

# ---- Configure --------------------------------------------------------------

echo "Setting Windows version to Windows 10..."
winetricks -q win10 || die "Failed to set the Windows version to win10."

echo "Installing .NET Framework 4.5.2 (this takes a while)..."
winetricks -q --force dotnet452 || die "Failed to install .NET Framework 4.5.2."

echo "Installing Microsoft core fonts..."
winetricks -q corefonts || die "Failed to install corefonts."

echo ""
echo "Prefix ready."
echo "  Location:        $WINEPREFIX"
echo "  Architecture:    win64"
echo "  Windows version: Windows 10"
echo "  Installed:       .NET Framework 4.5.2, Core Fonts"
echo ""

# ---- Installer discovery ----------------------------------------------------
# Reuse a launcher that is already on disk before pulling ~100MB again. Search
# order is cheapest first: working directory, prefix, the usual download spots,
# then a depth-limited sweep of $HOME. An unbounded find over $HOME can take
# minutes on a large drive, so the sweep stops at four levels.

find_installer() {
    local name="$1"
    local found=""

    local candidates=(
        "./$name"
        "$WINEPREFIX/$name"
        "$HOME/Downloads/$name"
        "$HOME/Desktop/$name"
        "$HOME/$name"
    )

    local c
    for c in "${candidates[@]}"; do
        if [ -f "$c" ] && [ -r "$c" ]; then
            found="$c"
            break
        fi
    done

    if [ -z "$found" ]; then
        # Newest match wins if several copies exist.
        found="$(find "$HOME" -maxdepth 4 -type f -iname "$name" -readable \
                 -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)"
    fi

    [ -n "$found" ] || return 1

    # Reject a stale or truncated file rather than feeding it to wine.
    if [ "$(head -c 2 "$found")" != "MZ" ]; then
        echo "Ignoring $found: not a valid Windows executable." >&2
        return 1
    fi

    printf '%s\n' "$found"
}

# ---- Installer acquisition --------------------------------------------------

download_installer() {
    local url="$1"
    local dest="$2"

    command -v curl >/dev/null 2>&1 || die "'curl' not found on PATH. Install curl or pass an installer path explicitly."

    echo "Downloading installer from: $url"
    curl -fL --progress-bar -o "$dest" "$url" || die "Download failed. Check the URL and your connection."

    [ -s "$dest" ] || die "Downloaded file is empty."

    # Windows PE executables begin with the ASCII bytes 'MZ'. If the endpoint
    # served an error page or an HTML redirect, catch it here rather than
    # handing wine something useless.
    if [ "$(head -c 2 "$dest")" != "MZ" ]; then
        die "Downloaded file is not a Windows executable. The endpoint may have returned an error page."
    fi

    echo "Downloaded: $dest ($(du -h "$dest" | cut -f1))"
}

if [ -n "$INSTALLER" ]; then
    [ -f "$INSTALLER" ] || die "Installer not found: $INSTALLER"
    [ -r "$INSTALLER" ] || die "Installer is not readable: $INSTALLER"
    echo "Using local installer: $INSTALLER"
else
    if [ "$FORCE_DOWNLOAD" -eq 0 ]; then
        echo "Looking for an existing $INSTALLER_NAME..."
        INSTALLER="$(find_installer "$INSTALLER_NAME")" || INSTALLER=""
    fi

    if [ -n "$INSTALLER" ]; then
        echo "Found existing launcher: $INSTALLER"
        echo "Use -f to force a fresh download instead."
    else
        [ "$FORCE_DOWNLOAD" -eq 1 ] || echo "No local copy found."
        if [ "$KEEP_INSTALLER" -eq 1 ]; then
            mkdir -p "$WINEPREFIX" || die "Could not create $WINEPREFIX"
            INSTALLER="$WINEPREFIX/$INSTALLER_NAME"
        else
            TMP_DIR="$(mktemp -d)" || die "Could not create a temporary directory."
            INSTALLER="$TMP_DIR/$INSTALLER_NAME"
        fi
        download_installer "$SEED_URL" "$INSTALLER"
    fi
fi

# ---- Run the installer ------------------------------------------------------

echo ""
echo "Launching installer under Wine..."
wine "$INSTALLER"
STATUS=$?

if [ "$KEEP_INSTALLER" -eq 1 ]; then
    echo ""
    echo "Installer kept at: $INSTALLER"
fi

exit $STATUS
