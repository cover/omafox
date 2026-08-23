# Omafox

Omafox keeps Firefox's interface in sync with your current
[Omarchy](https://omarchy.org/) theme.

## Features

- Automatically updates Firefox whenever you change your Omarchy theme.
- Themes tabs, toolbars, menus, sidebars, and the new tab page from the full
  Omarchy palette.
- Supports both dark and light themes, including custom themes with partial
  palettes.
- Restores your current theme when Firefox starts.
- Provides a small Firefox popup for sync status, manual reapplication, and
  clearing the applied theme.
- Runs entirely on your computer, with no account, network service, telemetry,
  or persistent daemon.

## Requirements

- Omarchy 4 (Quattro) or newer.
- Firefox 142 or newer.

## Installation

Omafox has two parts: the Firefox extension applies the theme, and the AUR
package connects Firefox to Omarchy. Install both:

1. Install the [Omafox extension for
   Firefox](https://addons.mozilla.org/en-US/firefox/addon/omafox/).
2. Install the [Omafox AUR package](https://aur.archlinux.org/packages/omafox):

   ```bash
   yay -S omafox
   ```

3. Enable theme syncing for your user:

   ```bash
   omafox setup
   ```

Setup registers the Omarchy theme-change hook and immediately sends your
current palette to Firefox. Run it once for each desktop user who wants to use
Omafox.

## Usage

After setup, use Omarchy as usual. Changing the theme automatically updates
Firefox:

```bash
omarchy theme set catppuccin
```

Click the Omafox button in Firefox to see the active Omarchy theme, palette
mode, last sync time, and connection status. The popup can also reapply the
stored theme or clear it from Firefox.

The command-line helper provides a few additional controls:

```bash
omafox status    # Show the current theme and integration state
omafox sync      # Send the current palette to Firefox again
omafox payload   # Print the current normalized theme message
omafox setup     # Reconfigure the integration for this user
omafox remove    # Remove this user's hook and saved theme state
omafox version   # Show the installed version
```

## How it works

Omafox is made up of three small parts:

- An Omarchy theme-change hook reads the current `colors.toml` palette and
  writes a normalized theme message to `~/.local/state/omafox/theme.json`.
- The native messaging host watches that file with Linux `inotify` and sends
  updates to Firefox. It sleeps between changes, so no persistent polling or
  background service is needed.
- The Firefox extension validates the message, maps the Omarchy colors to the
  closest Firefox theme properties, and saves the result in Firefox's local
  extension storage.

The flow is:

```text
Omarchy theme change
        ↓
Theme hook → local state file → native messaging host → Firefox extension
                                                        ↓
                                                  Firefox theme
```

When Firefox starts, the extension restores its saved theme and the native
host sends the latest Omarchy palette again. Everything stays local to the
machine; there is no web service or always-running daemon.

## Troubleshooting

If Firefox does not update after a theme change:

1. Confirm that both the Firefox extension and AUR package are installed.
2. Run `omafox status` and check that the theme state, native host, and native
   manifest are present.
3. Run `omafox setup`, followed by `omafox sync`.
4. Open the Omafox popup in Firefox to check its connection status or reapply
   the theme.

You can report reproducible problems on [GitHub
Issues](https://github.com/cover/omafox/issues).

## Privacy

Omafox makes no network requests and does not collect or transmit data. It
only reads your local Omarchy palette and passes it to Firefox through native
messaging. See the [privacy statement](PRIVACY.md) for details.

## Uninstallation

Remove the per-user integration before uninstalling the package:

```bash
omafox remove
sudo pacman -Rns omafox
```

Then remove the Omafox extension from Firefox's `about:addons` page. Omafox
does not modify other Omarchy hooks or desktop configuration.

## Acknowledgements

Omafox was inspired by [omazed](https://github.com/APS6/omazed), which provides
live Omarchy theme switching for the Zed editor.

Omafox is released under the [MIT License](LICENSE).
