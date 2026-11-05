# Omafox

Omafox keeps Firefox and Zen Browser in sync with your current
[Omarchy](https://omarchy.org/) theme.

## Features

- Automatically updates supported browsers whenever you change your Omarchy
  theme.
- Themes tabs, toolbars, menus, sidebars, and the new tab page from the full
  Omarchy palette.
- Maps the extension theme into Zen's workspace and toolbar interface through
  a small, managed profile stylesheet.
- Supports both dark and light themes, including custom themes with partial
  palettes.
- Restores your current theme when the browser starts.
- Provides a small extension popup for sync status, manual reapplication, and
  clearing the applied theme.
- Runs entirely on your computer, with no account, network service, telemetry,
  or persistent daemon.

## Requirements

- Omarchy 4 (Quattro) or newer.
- Firefox 142 or newer, or a current native Zen Browser installation.

Flatpak installations of Zen are not currently supported because their
sandbox cannot use the host native-messaging manifest installed by the
package.

## Installation

Omafox has two parts: the Gecko extension applies the theme, and the native
package connects the browser to Omarchy. The same signed extension works in
Firefox and Zen Browser. Install both:

1. Install the [Omafox extension for
   Firefox or Zen Browser](https://addons.mozilla.org/en-US/firefox/addon/omafox/)
2. Install the native package. Arch Linux removed Omafox from the AUR because
   it only works on Omarchy; an
   [open pull request](https://github.com/omacom/omarchy-pkgs/pull/1840)
   proposes adding it to the Omarchy packages. Until then, download the
   package files from the pull request and build and install them with
   `makepkg` (from the `base-devel` package group):

   ```bash
   mkdir -p omafox-package
   cd omafox-package
   curl -fLO https://raw.githubusercontent.com/omacom/omarchy-pkgs/refs/pull/1840/head/pkgbuilds/omafox/PKGBUILD
   curl -fLO https://raw.githubusercontent.com/omacom/omarchy-pkgs/refs/pull/1840/head/pkgbuilds/omafox/omafox.install
   makepkg -si
   ```

3. Enable theme syncing for your user:

   ```bash
   omafox setup
   ```

Setup registers the Omarchy theme-change hook and immediately sends your
current palette to every connected browser. If Zen has been launched at least
once, setup also detects the profiles in `~/.config/zen/profiles.ini`,
installs the Omafox CSS bridge into each existing profile, and enables the two
Zen preferences it needs. Restart Zen once after setup. Run setup once for
each desktop user who wants to use Omafox, and rerun it after creating a new
Zen profile.

If the theme does not update after setup, completely close and restart the
browser. If it still does not update, restart your system.

## Usage

After setup, use Omarchy as usual. Changing the theme automatically updates
Firefox and Zen:

```bash
omarchy theme set catppuccin
```

Click the Omafox button in either browser to see the active Omarchy theme,
palette mode, last sync time, and connection status. The popup can also
reapply the stored theme or clear it from that browser. In Zen, clearing the
theme disables the scoped CSS bridge and reveals Zen's normal workspace
theme again.

The command-line helper provides a few additional controls:

```bash
omafox status    # Show the current theme and integration state
omafox sync      # Queue the current palette for connected browsers
omafox payload   # Print the current normalized theme message
omafox setup     # Reconfigure the integration for this user
omafox remove    # Remove this user's hook and saved theme state
omafox version   # Show the installed version
```

## How it works

Omafox is made up of a few small parts:

- An Omarchy theme-change hook reads the current `colors.toml` palette and
  writes a normalized theme message to `~/.local/state/omafox/theme.json`.
- The native messaging host watches that file with Linux `inotify` and sends
  updates to connected browser extensions. It sleeps between changes, so no
  persistent polling or background service is needed.
- The extension validates the message, maps the Omarchy colors to standard
  Firefox theme properties, and saves the result in the browser's local
  extension storage.
- For Zen profiles, `omafox setup` installs
  `chrome/omafox.css`, adds a managed import to `chrome/userChrome.css`, and
  adds the required preferences to a managed block in `user.js`. Existing
  profile customizations outside those marked blocks are preserved. Setup
  refuses to overwrite an unrelated `chrome/omafox.css` file.

The flow is:

```text
Omarchy theme change
        ↓
Theme hook → local state file → native messaging host → browser extension
                                                        ↓
                                           Firefox theme properties
                                                        ↓
                                       Firefox UI or Zen CSS bridge
```

When a supported browser starts, the extension restores its saved theme and
the native host sends the latest Omarchy palette again. Everything stays
local to the machine; there is no web service or always-running daemon.

## Troubleshooting

If a browser does not update after a theme change:

1. Confirm that both the Omafox extension and native package are installed.
2. Run `omafox status` and check that the theme state, native host, and native
   manifest are present. For Zen, also check that each profile says
   `configured`. A `conflict` status means the profile already contains an
   unrelated `chrome/omafox.css`; rename or remove that file before setup.
3. Run `omafox setup`, followed by `omafox sync`.
4. Completely close and restart the browser. Zen also requires a restart if
   its bridge was newly installed or updated.
5. Open the Omafox popup to check its connection status or reapply the theme.
6. If the theme still does not update, restart your system.

You can report reproducible problems on [GitHub
Issues](https://github.com/cover/omafox/issues).

## Privacy

Omafox makes no network requests and does not collect or transmit data. It
only reads your local Omarchy palette and passes it to supported browsers
through native messaging. Zen support additionally writes the managed local
profile files described above. See the [privacy statement](PRIVACY.md) for
details.

## Uninstallation

Remove the per-user integration before uninstalling the package:

```bash
omafox remove
sudo pacman -Rns omafox
```

Then remove the Omafox extension from Firefox's `about:addons` page. Omafox
can be removed from Zen on the same page. Restart Zen after removal. The
command deletes the Omafox stylesheet and its managed `userChrome.css` and
`user.js` blocks without removing other profile customizations.

Zen copies `user.js` values into `prefs.js` when it starts, so the preferences
`toolkit.legacyUserProfileCustomizations.stylesheets` and
`zen.theme.disable-lightweight` may remain as user-set values after removal.
Use Reset for those entries in `about:config` if you want to return them to
Zen's defaults.

## Acknowledgements

Omafox was inspired by [omazed](https://github.com/APS6/omazed), which provides
live Omarchy theme switching for the Zed editor.

Omafox is released under the [MIT License](LICENSE).
