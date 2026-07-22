#!/bin/bash
#####################################################################################
# Author: Tempus Thales
# Version: 0.05
# Date: 07/22/2026
# Description: Install and run seed.game on Linux under Proton via umu-launcher.
#
# Proton is not a drop-in for the wine binary. It expects Steam's environment and
# runs inside the Steam Linux Runtime container. umu-launcher supplies that
# environment outside of Steam, so this script drives umu-run rather than wine.
#
# There is no native Linux build of seed.game. This script downloads and runs the
# official Windows installer inside a Proton prefix.
#
# EXPERIMENTAL. Companion to install_seed_wine.sh, which is the known-good path.
#
# Credit: Wine version based on the original script shared by King Peky.
#####################################################################################
# Changelog:
#
# 0.05 - 07/22/2026 - Full run logging to a timestamped file in the prefix dir
#                   - Log opens with an environment header (OS, kernel, Proton
#                     build, GAMEID, umu-run version) for later debugging
#                   - Added -L to override the log path
#
# 0.04 - 07/22/2026 - Removed the umu-run empty-argument prefix step. Testing
#                     showed umu treats "" as an executable path and fails with
#                     "File not found" rather than creating the prefix and
#                     exiting. umu builds the prefix as a side effect of running
#                     a program, so the installer run now creates the prefix.
#                   - Installer download and discovery moved ahead of the umu
#                     call so there is a real program to run.
#                   - Optional -d / -c winetricks steps moved to after the
#                     installer, since the prefix does not exist until then.
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
#                   - Added -k to keep the downloaded installer
#                   - Downloaded file is checked for the MZ header so an error
#                     page never reaches Proton
#
# 0.01 - 07/19/2026 - Initial version
#                   - Prefix creation attempted via umu-run empty argument
#                     (removed in 0.04, see below)
#                   - Optional .NET 4.5.2 install, off by default (see notes)
#                   - Proton build selectable, defaults to GE-Proton
#                   - Guards against stock Valve Proton when winetricks verbs are
#                     requested, since umu only supports verbs on GE/UMU-Proton
#####################################################################################

set -o pipefail

SCRIPT_NAME="$(basename "$0")"
SCRIPT_VERSION="0.05"

# Version-agnostic endpoint. Always serves the current stable Windows x64 build.
SEED_URL="https://launcher.seed.game/latest/stable/win/x64"

# Filename the launcher is distributed as. Used for local discovery.
INSTALLER_NAME="seed-launcher.exe"

# GE-Proton and UMU-Proton are the only builds umu supports winetricks verbs on.
PROTON_BUILD="GE-Proton"
GAME_ID="umu-default"
INSTALL_DOTNET=0
INSTALL_COREFONTS=0
KEEP_INSTALLER=0
FORCE_DOWNLOAD=0
LOG_PATH=""
TMP_DIR=""

usage() {
    cat <<EOF
Usage: $SCRIPT_NAME [options] <prefix_path> [installer_path]

Install seed.game under Proton using umu-launcher.

With no installer_path, an existing seed-launcher.exe is located on disk.
If none is found, the official launcher is downloaded automatically.

Arguments:
  prefix_path       Path to the prefix. Created if it does not exist.
  installer_path    Optional. Use a local installer instead of downloading.

Options:
  -u <url>          Override the installer download URL.
                    Default: $SEED_URL
  -k                Keep the downloaded installer in the prefix directory.
  -f                Force a fresh download, ignoring any local copy.
  -L <path>         Write the run log to <path> instead of the prefix dir.
  -P <build>        Proton build. Path, version name, or codename.
                    Default: $PROTON_BUILD
  -g <gameid>       umu GAMEID for protonfixes lookup. Default: $GAME_ID
  -d                Install .NET Framework 4.5.2. Off by default; Proton ships
                    Wine Mono, which handles many .NET apps without it.
  -c                Install Microsoft core fonts. Off by default; Proton ships
                    font substitutions that usually cover this.
  -h, --help, /?    Show this help and exit.

Examples:
  $SCRIPT_NAME ~/.seed-proton
  $SCRIPT_NAME -k ~/.seed-proton
  $SCRIPT_NAME -d ~/.seed-proton
  $SCRIPT_NAME ~/.seed-proton ~/Downloads/seed-setup.exe

Notes:
  Try a bare run first. Only add -d if the game fails on Wine Mono. Installing
  Microsoft .NET over Wine Mono in a Proton prefix is known to be fragile.
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

while getopts ":u:kfL:P:g:dch" opt; do
    case "$opt" in
        u) SEED_URL="$OPTARG" ;;
        k) KEEP_INSTALLER=1 ;;
        f) FORCE_DOWNLOAD=1 ;;
        L) LOG_PATH="$OPTARG" ;;
        P) PROTON_BUILD="$OPTARG" ;;
        g) GAME_ID="$OPTARG" ;;
        d) INSTALL_DOTNET=1 ;;
        c) INSTALL_COREFONTS=1 ;;
        h) usage; exit 0 ;;
        :) die "Option -$OPTARG requires an argument." ;;
        \?) die "Unknown option: -$OPTARG. Use -h for help." ;;
    esac
done
shift $((OPTIND - 1))

[ -n "$1" ] || { usage; exit 1; }

PREFIX_ARG="$1"
INSTALLER="$2"

# ---- Dependency check -------------------------------------------------------

command -v umu-run >/dev/null 2>&1 || die "'umu-run' not found on PATH. Install umu-launcher (Arch: pacman -S umu-launcher)."

# ---- Winetricks verb support check ------------------------------------------
# umu only exposes the winetricks positional argument on GE-Proton and
# UMU-Proton builds. Stock Valve Proton will not accept the verbs, so fail
# early with a useful message rather than partway through setup.

if [ "$INSTALL_DOTNET" -eq 1 ] || [ "$INSTALL_COREFONTS" -eq 1 ]; then
    case "$PROTON_BUILD" in
        *GE-Proton*|*UMU-Proton*)
            : ;;
        *)
            die "winetricks verbs (-d / -c) require a GE-Proton or UMU-Proton build. Current: $PROTON_BUILD"
            ;;
    esac
fi

# ---- Resolve prefix path ----------------------------------------------------

WINEPREFIX="$(realpath -m "$PREFIX_ARG")" || die "Could not resolve prefix path: $PREFIX_ARG"
export WINEPREFIX
export PROTONPATH="$PROTON_BUILD"
export GAMEID="$GAME_ID"

# ---- Logging setup ----------------------------------------------------------
# Capture the full run, script output plus umu/Proton output, to a timestamped
# file. tee keeps it on screen while writing to disk. The redirect is placed
# here, after the prefix path is known, so the log lands in the right spot;
# everything printed from this point on is captured.

if [ -z "$LOG_PATH" ]; then
    mkdir -p "$WINEPREFIX" || die "Could not create $WINEPREFIX"
    LOG_PATH="$WINEPREFIX/install-$(date +%Y%m%d-%H%M%S).log"
fi

# Header block: the environment details worth having when debugging later.
{
    echo "#############################################################"
    echo "# seed.game Proton install log"
    echo "# Script:   $SCRIPT_NAME v$SCRIPT_VERSION"
    echo "# Date:     $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo "# Prefix:   $WINEPREFIX"
    echo "# Proton:   $PROTON_BUILD"
    echo "# GAMEID:   $GAME_ID"
    echo "# OS:       $(if . /etc/os-release 2>/dev/null && [ -n "$PRETTY_NAME" ]; then echo "$PRETTY_NAME"; else uname -s; fi)"
    echo "# Kernel:   $(uname -r)"
    echo "# umu-run:  $(umu-run --version 2>/dev/null | head -1 || echo 'unknown')"
    echo "#############################################################"
    echo ""
} > "$LOG_PATH"

# Route all subsequent stdout and stderr through tee to the log.
exec > >(tee -a "$LOG_PATH") 2>&1

echo "Logging to: $LOG_PATH"
echo ""

if [ -d "$WINEPREFIX" ]; then
    echo "Using existing prefix: $WINEPREFIX"
else
    echo "Creating new prefix: $WINEPREFIX"
fi

echo "Proton build: $PROTON_BUILD"
echo "Game ID:      $GAME_ID"
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
    # handing Proton something useless.
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
# umu does not have a separate prefix-creation step. It builds the prefix as a
# side effect of running a program, downloading Proton and the Steam Linux
# Runtime on a cold cache. So running the installer here is also what creates
# the prefix.

echo ""
echo "Launching installer under Proton (first run downloads Proton and the runtime)..."
umu-run "$INSTALLER"
STATUS=$?

[ "$STATUS" -eq 0 ] || die "Installer exited with status $STATUS."

echo ""
echo "Prefix ready and installer finished."
echo "  Prefix:  $WINEPREFIX"
echo "  Proton:  $PROTON_BUILD"
echo "  Game ID: $GAME_ID"

# ---- Optional winetricks verbs ----------------------------------------------
# These run after the installer because the prefix only exists once umu has run
# a program. If the game needs .NET or fonts, they are applied to the completed
# prefix here.

if [ "$INSTALL_DOTNET" -eq 1 ]; then
    echo ""
    echo "Installing .NET Framework 4.5.2..."
    umu-run winetricks -q --force dotnet452 || die "Failed to install .NET Framework 4.5.2."
    echo "  Extra:   .NET Framework 4.5.2"
fi

if [ "$INSTALL_COREFONTS" -eq 1 ]; then
    echo ""
    echo "Installing Microsoft core fonts..."
    umu-run winetricks -q corefonts || die "Failed to install corefonts."
    echo "  Extra:   Core Fonts"
fi

if [ "$KEEP_INSTALLER" -eq 1 ]; then
    echo ""
    echo "Installer kept at: $INSTALLER"
fi

exit $STATUS