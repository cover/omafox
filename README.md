# Omafox

Omafox keeps Firefox's browser chrome in sync with the current Omarchy
palette. It consists of:

- `extension/`, the separately distributed Firefox extension.
- `omarchy/omafox`, the user-facing command and Omarchy hook target.
- `omarchy/omafox-native-host.c`, the small Firefox native messaging host.
- a separately maintained [AUR package](https://aur.archlinux.org/packages/omafox)
  that installs the command and compiled native host system-wide.

Omafox was inspired by [omazed](https://github.com/APS6/omazed), which provides
live Omarchy theme switching for the Zed editor.

There is no persistent daemon and no web service. When Omarchy changes theme,
the hook reads Omarchy's `colors.toml` and atomically stores a JSON protocol
message in `~/.local/state/omafox/theme.json`. While Firefox is running, the
native host uses Linux `inotify` to sleep until that file changes and then
forwards the message through Firefox native messaging.

The extension applies the palette and retains it in `storage.local`. When
Firefox starts again, the native host immediately sends the latest state. The
command updates that state on every sync, so Firefox always receives the
latest palette when it is running.

## Requirements

Runtime requirements:

- Omarchy 4 (Quattro) or newer.
- Firefox 142 or newer with the
  [Omafox extension](https://addons.mozilla.org/en-US/firefox/addon/omafox)
  installed separately.

Building from source requires a C17 compiler and Make. On Arch, the
`base-devel` group provides the required toolchain. The test suite additionally
uses Node.js, Python 3, and ShellCheck.

## Firefox extension

The Firefox extension is distributed separately from the Arch package. For
development, open `about:debugging#/runtime/this-firefox`, choose **Load
Temporary Add-on**, and select `extension/manifest.json`.

Temporary add-ons are removed when Firefox exits. A permanent installation in
normal Firefox requires a Mozilla-signed XPI:

```bash
cd extension
./build.sh
```

For the first public release, upload the generated XPI through the
[AMO Developer Hub](https://addons.mozilla.org/developers/) and choose **On
this site**. For later updates to the public listing, Mozilla's `web-ext`
utility can submit the extension with AMO API credentials:

```bash
npx web-ext sign --channel listed --source-dir . \
  --artifacts-dir dist \
  --ignore-files build.sh 'dist/**' \
  --api-key "$AMO_JWT_ISSUER" \
  --api-secret "$AMO_JWT_SECRET"
```

Omafox makes no network requests and does not collect or transmit data. See
the [privacy statement](PRIVACY.md) for details.

## Arch/AUR installation

```bash
yay -S omafox
omafox setup
```

The first command builds the C host while creating the Arch package, then
pacman installs the already-compiled result. A compiler is not needed when
running Omafox afterward. The second command runs as the desktop user and:

- installs `~/.config/omarchy/hooks/theme-set.d/omafox` using Omarchy's hook
  command;
- writes the current palette for the native host.

The package owns these system files:

- `/usr/bin/omafox`
- `/usr/lib/omafox/omafox-native-host`
- `/usr/lib/mozilla/native-messaging-hosts/org.omarchy.omafox.json`
- `/usr/share/omafox/hooks/omafox`
- documentation and the MIT license under `/usr/share`

Pacman never writes into a user's home directory. Per-user setup is kept
explicit because package operations run as root and cannot safely select a
desktop user.

## Usage

```bash
omafox sync                 # Queue the palette for Firefox
omafox payload              # Print the current JSON protocol message
omafox status               # Show the theme and integration state
omafox setup                # Enable/reconfigure the current user's integration
omafox remove               # Remove the current user's hook and state
omafox version              # Print the installed version
```

Changing the Omarchy theme normally is all that is needed:

```bash
omarchy theme set catppuccin
```

## Removal

Remove the user integration before removing the pacman-owned files:

```bash
omafox remove
sudo pacman -Rns omafox
```

Then remove the separately installed extension from `about:addons`. Omafox
does not modify other Omarchy hooks or desktop configuration.

## Native protocol

The versioned `theme-set` message has this shape (palette abbreviated):

```json
{
  "protocol": "omafox",
  "version": 1,
  "action": "theme-set",
  "theme": "osaka-jade",
  "palette": {
    "mode": "dark",
    "accent": "#509475"
  }
}
```

The real `palette` contains all 26 normalized Omarchy fields. This private JSON
protocol is carried only through native messaging. The extension makes no
network requests and does not request access to browsing history or website
contents.

The native host frames and forwards the JSON object without interpreting it.
The extension accepts only protocol `omafox`, version `1`, and action
`theme-set`; it also requires exactly the Omarchy palette keys and validates
every color before applying anything. Firefox has fewer independently
themeable UI slots than Omarchy, so every value is retained in extension
storage while the closest semantic colors are mapped onto Firefox theme
properties.

Omafox preserves valid supplied colors but does not reject an incomplete
custom palette. It normalizes `#RGB` and `0xRRGGBB`, infers a missing mode from
the background, derives surface and text variants, and supplies
mode-appropriate semantic colors. Bright colors derive from their normal
counterparts; `orange` falls back to `yellow` and `brown` to `muted`.

## Build

```bash
make

# Test the staged package filesystem without installing it:
staging=$(mktemp -d)
make DESTDIR="$staging" PREFIX=/usr install
```

The suite validates protocol messages, Firefox theme mapping, native messaging
framing and `inotify` delivery, state updates, the system package layout, and
per-user packaged setup. The suite runs in Alpine Linux through GitHub Actions
for every push and pull request.
