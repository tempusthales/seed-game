# seed-game

Setup scripts for running seed.game on Linux. Two backends, two different levels
of confidence.

| Script | Backend | Status |
| --- | --- | --- |
| `install_seed_wine.sh` | Wine + winetricks | Working |
| `install_seed_proton.sh` | Proton via umu-launcher | **Experimental. Unverified.** |

Both build a 64-bit prefix and optionally launch an executable inside it. What
happens underneath is where they diverge.

---

## install_seed_wine.sh

The known-good path. A hardened version of a script that people have actually
used to get the game running.

### What it does

| Stage | Command | Why |
| --- | --- | --- |
| Create prefix | `wineboot -u` | Builds `drive_c`, registry hives, default DLL overrides |
| Synchronize | `wineserver -w` | Blocks until wineboot's background work finishes |
| Set OS version | `winetricks win10` | Many installers refuse to run on Wine's older default |
| Runtime | `winetricks --force dotnet452` | .NET Framework 4.5.2 |
| Fonts | `winetricks corefonts` | Arial, Times New Roman, and friends |

Every stage checks its exit status. A failed `wineboot` or a half-finished
`dotnet452` install stops the run instead of printing "complete" and carrying on.

### Requirements

`wine` and `winetricks`. The script verifies `wine`, `wineboot`, `wineserver`,
and `winetricks` are on PATH before touching anything.

```bash
# Arch / CachyOS
sudo pacman -S wine winetricks

# Debian / Ubuntu
sudo apt install wine winetricks

# Fedora
sudo dnf install wine winetricks
```

### Usage

```
install_seed_wine.sh <wineprefix_path> [executable_path]
```

```bash
# Prefix only
./install_seed_wine.sh ~/.seed-game

# Prefix, then launch
./install_seed_wine.sh ~/.seed-game /path/to/seed.exe

# Help
./install_seed_wine.sh -h
```

### Notes

- The prefix path is resolved to an absolute path. Wine rejects relative
  `WINEPREFIX` values.
- `WINEARCH=win64` only applies when a prefix is created. Point the script at an
  existing 32-bit prefix and it refuses, rather than letting Wine throw a
  confusing architecture mismatch.
- `wineserver -w` waits for every process in the prefix to exit. If something is
  already running there, this blocks.
- Uses GNU coreutils `realpath -m`. On macOS you would need
  `brew install coreutils` and a `grealpath` substitution. Linux is the target.

---

## install_seed_proton.sh

**This is an experiment.** It has never been run against a real `umu-run`
installation. Every branch was tested against a stubbed binary, so the argument
parsing, guards, and exit codes behave correctly, but nothing here is confirmed
to produce a working game.

Treat it as a hypothesis to test, not a tool to rely on.

### The question it exists to answer

Proton 11.0 is based on Wine 11.0 and bundles components the plain Wine path has
to install by hand. If Proton's built-in Wine Mono handles seed.game's .NET
requirements, the Proton path is dramatically simpler: no `dotnet452`, no
`corefonts`, no `win10`, no `wineboot`. One command instead of five stages.

If it doesn't, this script is a dead end and the Wine version remains the answer.

### Why it can't just call `wine`

Proton is not a drop-in for the `wine` binary. It expects Steam's environment
variables and runs inside the Steam Linux Runtime container. Calling `wineboot`
or `winetricks` against a Proton prefix directly does not work.

umu-launcher exists to supply that environment outside of Steam, giving other
launchers a standard way to run games through Proton. So this script drives
`umu-run` rather than `wine`.

### What it does

| Stage | Command | Notes |
| --- | --- | --- |
| Create prefix | `umu-run ""` | The empty-argument form builds the prefix and exits |
| .NET (optional) | `umu-run winetricks --force dotnet452` | Off by default |
| Fonts (optional) | `umu-run winetricks corefonts` | Off by default |

### Requirements

`umu-launcher`.

```bash
# Arch / CachyOS
sudo pacman -S umu-launcher
```

### Usage

```
install_seed_proton.sh [options] <prefix_path> [executable_path]
```

| Option | Effect |
| --- | --- |
| `-P <build>` | Proton build. Path, version name, or codename. Default `GE-Proton` |
| `-g <gameid>` | umu GAMEID for protonfixes lookup. Default `umu-default` |
| `-d` | Install .NET Framework 4.5.2. Off by default |
| `-c` | Install Microsoft core fonts. Off by default |
| `-h` | Help |

```bash
# Start here
./install_seed_proton.sh ~/.seed-proton /path/to/seed.exe

# Only if the bare run fails on Wine Mono
./install_seed_proton.sh -d ~/.seed-proton /path/to/seed.exe
```

### Why .NET and fonts are opt-in

Proton bundles Wine Mono 11.0.0, its own .NET implementation, which handles many
.NET applications without Microsoft's runtime. Installing real .NET over Wine
Mono in a Proton prefix is known to be fragile.

Proton also ships font substitutions that usually cover what corefonts provides.

Run bare first. Add flags only when something actually breaks. Turning both on up
front defeats the purpose, since you would not learn whether they were needed.

### GE-Proton requirement for winetricks verbs

umu only exposes winetricks verbs on GE-Proton and UMU-Proton builds. Stock
Valve Proton will not accept them. The script defaults to `GE-Proton` and
refuses `-d` or `-c` if pointed at a stock build.

This matters: if seed.game turns out to need real .NET, stock Proton 11.0 is not
an option for that path.

### Open questions

Answering these is the point of the experiment.

1. Does seed.game run on Wine Mono, or does it need Microsoft .NET? This decides
   whether the whole Proton approach is viable.
2. Does `umu-run winetricks` pass `-q` and `--force` through to winetricks? The
   man page documents bare verbs only. If it chokes, drop those flags.
3. Does `umu-run ""` reliably exit 0 after creating a prefix? The empty-argument
   form comes from the umu man page examples but has not been verified here.
4. First run downloads Proton and the Steam Linux Runtime. Large cold-cache
   download with no progress feedback beyond umu's own output.

### If you test this

Results are welcome. Open an issue with your distro, Proton build, umu-launcher
version, and what happened. Negative results are as useful as positive ones,
since the goal is to find out whether the port is possible at all.

---

## Install

```bash
chmod +x install_seed_wine.sh install_seed_proton.sh
sudo cp install_seed_wine.sh /usr/local/bin/install-seed-wine
sudo cp install_seed_proton.sh /usr/local/bin/install-seed-proton
```

## Credit

Wine version based on the original script shared by King Peky, in the SEED Discord: [https://discord.gg/seedgame](https://discord.gg/seedgame)

## License

MIT. See [LICENSE](LICENSE).
