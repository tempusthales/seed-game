# seed-launcher-linux

Run [seed.game](https://seed.game) on Linux. There is no native Linux build, so
each method runs the official Windows launcher through a compatibility layer.

Three methods, in order of recommendation:

| Method | Engine | Who it's for | Status |
| --- | --- | --- | --- |
| Steam + Proton | Proton (Steam-managed) | Most people. Best integration. | **Recommended** |
| umu + Proton | Proton (GE, via umu) | Proton without Steam, fully scriptable | Working |
| Wine + winetricks | Wine (no Proton) | No Steam, no umu, or a Wine preference | Working, fallback |

All three run the same launcher (`SeedLauncher.exe`), which handles login and
downloads the game client itself. The difference is only what builds and manages
the Windows environment underneath.

The scripts here automate the install for the umu + Proton and Wine methods.
The Steam method is a short manual walkthrough, since its final step
(registering the shortcut) cannot be scripted safely.

---

## Method 1: Steam + Proton (recommended)

If you already run Steam, this is the least fuss and the best result. Steam
manages the Proton version and prefix, and you get library integration, the
overlay, playtime tracking, and controller support for free.

### Walkthrough

1. **Get the launcher.** Download it into a permanent folder (not a temporary
   one, Steam points at this path every launch):

   ```bash
   mkdir -p ~/Games/SEED
   curl -fL -o ~/Games/SEED/seed-launcher.exe \
     https://launcher.seed.game/latest/stable/win/x64
   ```

2. **Add it to Steam.** Steam menu: **Games -> Add a Non-Steam Game to Steam ->
   Browse**, navigate to `~/Games/SEED/`, select `seed-launcher.exe`, then
   **Add Selected Programs**.

3. **Force Proton.** This step is essential. Without it, Steam tries to run a
   Windows executable directly and it fails instantly. Right-click the new
   entry -> **Properties -> Compatibility -> Force the use of a specific Steam
   Play compatibility tool**, then pick **Proton Experimental** (or a recent
   numbered Proton, or GE-Proton if you have it installed in Steam).

4. **Rename and icon (optional).** On the same Properties screen, General tab,
   rename the entry to `SEED`. To set the icon, click the icon box on that
   screen and point it at `SEED_Logo.jpg` from this repo.

5. **Launch.** Hit **Play**. Steam builds a fresh prefix on first launch, so the
   launcher then authenticates and downloads the game client. This takes a
   while the first time.

That's it. The launcher opens, you log in on the portal, and the game installs
and runs inside Steam's prefix.

### Notes

- Steam does not reuse a prefix built by the umu method below. It creates its
  own under `~/.local/share/Steam/steamapps/compatdata/<appid>/`.
- If the launcher does not appear after hitting Play, the force-Proton step
  (step 3) was almost certainly skipped. That is the single most common mistake.

---

## Method 2: umu + Proton (scriptable, no Steam)

Same Proton engine as the Steam method, driven by [umu-launcher](https://github.com/Open-Wine-Components/umu-launcher)
instead of Steam. Good if you do not run Steam but still want Proton, or you
want the whole thing scripted.

Proton is not a drop-in for the `wine` binary. It expects Steam's environment
and runs inside the Steam Linux Runtime container. umu supplies that environment
outside of Steam, so these scripts drive `umu-run`.

### Requirements

```bash
# Arch / CachyOS
sudo pacman -S umu-launcher
```

`curl` is also needed for the automatic download.

### Install

```bash
chmod +x install_seed_proton.sh
./install_seed_proton.sh ~/.seed-proton
```

This creates the prefix at `~/.seed-proton`, downloads `SeedLauncher.exe` (or
reuses a local copy if found), and runs it so you can log in and let it install
the game. On first run it also downloads GE-Proton and the Steam Linux Runtime,
which is a large one-time download.

| Option | Effect |
| --- | --- |
| `-u <url>` | Override the launcher download URL |
| `-k` | Keep the downloaded launcher in the prefix |
| `-f` | Force a fresh download, ignoring any local copy |
| `-L <path>` | Write the run log somewhere other than the prefix |
| `-P <build>` | Proton build. Default `GE-Proton` |
| `-g <gameid>` | umu GAMEID for protonfixes. Default `umu-default` |
| `-d` | Install .NET Framework 4.5.2 (see note) |
| `-c` | Install Microsoft core fonts |
| `-h` | Help |

**On `-d` and `-c`:** leave them off. Proton bundles Wine Mono, which runs the
launcher without Microsoft .NET. Testing confirmed the launcher works with no
extra components. Only reach for `-d` if a future version of the game fails on a
.NET error. These verbs also require a GE-Proton or UMU-Proton build; stock
Valve Proton will not accept them.

### Launching after install

The install script runs the launcher once so you can log in and install the
game. To start the game again later, run the launcher through umu directly:

```bash
WINEPREFIX=~/.seed-proton PROTONPATH=GE-Proton GAMEID=umu-default \
  umu-run ~/.seed-proton/drive_c/users/steamuser/AppData/Local/seedlauncher/SeedLauncher.exe
```

Point umu at `SeedLauncher.exe`, the stable launcher path, rather than the game
client directly, so login and self-updates keep working across game patches. If
you want this as a desktop shortcut or a Steam entry, see Method 1 for the Steam
route, which handles that for you.

---

## Method 3: Wine + winetricks (fallback)

The from-scratch path, no Proton. Use this only if you want neither Steam nor
umu, or you specifically prefer plain Wine. It builds a 64-bit prefix, reports
Windows 10, and installs .NET Framework 4.5.2 and the core fonts by hand before
running the launcher.

### Requirements

```bash
# Arch / CachyOS
sudo pacman -S wine winetricks

# Debian / Ubuntu
sudo apt install wine winetricks

# Fedora
sudo dnf install wine winetricks
```

### Install

```bash
chmod +x install_seed_wine.sh
./install_seed_wine.sh ~/.seed-game
```

Creates the prefix, configures it, downloads the launcher (or reuses a local
copy), and runs it.

| Option | Effect |
| --- | --- |
| `-u <url>` | Override the launcher download URL |
| `-k` | Keep the downloaded launcher in the prefix |
| `-f` | Force a fresh download, ignoring any local copy |
| `-L <path>` | Write the run log somewhere other than the prefix |
| `-h` | Help |

### Notes

- The prefix path is resolved to an absolute path. Wine rejects relative
  `WINEPREFIX` values.
- Point it at an existing 32-bit prefix and it refuses, rather than letting Wine
  throw a confusing architecture mismatch.
- `wineserver -w` waits for every process in the prefix to exit. If something is
  already running there, this blocks.

---

## Logs

The umu and Wine install scripts write a timestamped log into the prefix
directory (`install-YYYYMMDD-HHMMSS.log`), opening with an environment header
(OS, kernel, engine versions). The launch script writes `launch-*.log` the same
way. Use `-L <path>` on the install scripts to write elsewhere. These are the
first thing to check if a run misbehaves.

## Portability

The scripts target Linux and use GNU coreutils (`realpath -m`, `find -printf`,
`find -readable`) and bash process substitution. They are not written to run on
macOS or BSD.

## Credit

The Wine method is based on an original script shared by King Peky.

## License

MIT. See [LICENSE](LICENSE).
