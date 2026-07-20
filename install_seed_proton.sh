#!/bin/bash
#####################################################################################
# Author: Tempus Thales
# Version: 0.01
# Date: 07/19/2026
# Description: Bootstrap a Proton prefix for seed.game via umu-launcher.
#
# Proton is not a drop-in for the wine binary. It expects Steam's environment and
# runs inside the Steam Linux Runtime container. umu-launcher supplies that
# environment outside of Steam, so this script drives umu-run rather than wine.
#
# Companion to install_seed_wine.sh. Same job, different backend.
#
# Credit: Wine version based on the original script shared by King Peky.
#####################################################################################
# Changelog:
#
# 0.01 - 07/19/2026 - Initial version
#                   - Prefix creation via umu-run with an empty executable argument
#                   - Optional .NET 4.5.2 install, off by default (see notes)
#                   - Proton build selectable, defaults to GE-Proton
#                   - Guards against stock Valve Proton when winetricks verbs are
#                     requested, since umu only supports verbs on GE/UMU-Proton
#####################################################################################

set -o pipefail

SCRIPT_NAME="$(basename "$0")"

# GE-Proton and UMU-Proton are the only builds umu supports winetricks verbs on.
PROTON_BUILD="GE-Proton"
GAME_ID="umu-default"
INSTALL_DOTNET=0
INSTALL_COREFONTS=0

usage() {
    cat <<EOF
Usage: $SCRIPT_NAME [options] <prefix_path> [executable_path]

Bootstrap a Proton prefix using umu-launcher.

Arguments:
  prefix_path       Path to the prefix. Created if it does not exist.
  executable_path   Optional. Windows executable to run once setup finishes.

Options:
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
  $SCRIPT_NAME -P GE-Proton -d ~/.seed-proton /path/to/seed.exe
  $SCRIPT_NAME -g umu-default ~/.seed-proton

Notes:
  Try a bare run first. Only add -d if the game fails on Wine Mono. Installing
  Microsoft .NET over Wine Mono in a Proton prefix is known to be fragile.
EOF
}

die() {
    echo "Error: $*" >&2
    exit 1
}

# ---- Option parsing ---------------------------------------------------------

case "$1" in
    --help|/\?|"")
        usage
        [ -z "$1" ] && exit 1
        exit 0
        ;;
esac

while getopts ":P:g:dch" opt; do
    case "$opt" in
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
EXECUTABLE="$2"

# ---- Dependency check -------------------------------------------------------

command -v umu-run >/dev/null 2>&1 || die "'umu-run' not found on PATH. Install umu-launcher (Arch: pacman -S umu-launcher)."

# ---- Winetricks verb support check ------------------------------------------
# umu only exposes the winetricks positional argument on GE-Proton and
# UMU-Proton builds. Stock Valve Proton will not accept the verbs, so fail
# early with a useful message rather than partway through setup.

if [ "$INSTALL_DOTNET" -eq 1 ] || [ "$INSTALL_COREFONTS" -eq 1 ]; then
    case "$PROTON_BUILD" in
        GE-Proton*|UMU-Proton*|*"GE-Proton"*|*"UMU-Proton"*)
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

if [ -d "$WINEPREFIX" ]; then
    echo "Using existing prefix: $WINEPREFIX"
else
    echo "Creating new prefix: $WINEPREFIX"
fi

echo "Proton build: $PROTON_BUILD"
echo "Game ID:      $GAME_ID"
echo ""

# ---- Create the prefix ------------------------------------------------------
# An empty executable argument tells umu to build the prefix and exit. The first
# run also downloads the Proton build and Steam Linux Runtime if absent, which
# takes a while on a cold cache.

echo "Initializing prefix (first run downloads Proton and the runtime)..."
umu-run "" || die "umu-run failed to create the prefix."

# ---- Optional winetricks verbs ----------------------------------------------

if [ "$INSTALL_DOTNET" -eq 1 ]; then
    echo "Installing .NET Framework 4.5.2..."
    umu-run winetricks -q --force dotnet452 || die "Failed to install .NET Framework 4.5.2."
fi

if [ "$INSTALL_COREFONTS" -eq 1 ]; then
    echo "Installing Microsoft core fonts..."
    umu-run winetricks -q corefonts || die "Failed to install corefonts."
fi

echo ""
echo "Proton prefix ready."
echo "  Prefix:  $WINEPREFIX"
echo "  Proton:  $PROTON_BUILD"
echo "  Game ID: $GAME_ID"
[ "$INSTALL_DOTNET" -eq 1 ] && echo "  Extra:   .NET Framework 4.5.2"
[ "$INSTALL_COREFONTS" -eq 1 ] && echo "  Extra:   Core Fonts"

# ---- Optionally run the executable ------------------------------------------

if [ -n "$EXECUTABLE" ]; then
    [ -f "$EXECUTABLE" ] || die "Executable not found: $EXECUTABLE"
    [ -r "$EXECUTABLE" ] || die "Executable is not readable: $EXECUTABLE"

    echo ""
    echo "Running: $EXECUTABLE"
    umu-run "$EXECUTABLE"
    exit $?
fi

exit 0