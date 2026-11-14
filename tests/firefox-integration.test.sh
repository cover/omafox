#!/bin/bash

set -euo pipefail

TEST_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_DIR=$(dirname "$TEST_DIR")
TEST_ROOT=$(mktemp -d)
TEST_HOME="$TEST_ROOT/home"
MOCK_BIN="$TEST_ROOT/bin"
THEME_DIR="$TEST_ROOT/theme"
FIREFOX_ROOT="$TEST_HOME/.config/mozilla/firefox"
RELATIVE_PROFILE="$FIREFOX_ROOT/abc123.default-release"
ABSOLUTE_PROFILE="$TEST_ROOT/external Firefox profile"
MISSING_PROFILE="$FIREFOX_ROOT/missing.default"
NATIVE_HOST="$TEST_ROOT/package/omafox-native-host"
NATIVE_MANIFEST="$TEST_ROOT/package/org.omarchy.omafox.json"
HOOK_SOURCE="$TEST_ROOT/package/omafox-hook"
BLANK_MARKER='/* OMAFOX FIREFOX BLANK PAGE MANAGED FILE */'
CSS_BEGIN='/* BEGIN OMAFOX FIREFOX BLANK PAGE */'
CSS_END='/* END OMAFOX FIREFOX BLANK PAGE */'
PREFS_BEGIN='// BEGIN OMAFOX FIREFOX BLANK PAGE'
PREFS_END='// END OMAFOX FIREFOX BLANK PAGE'
CHROME_BEGIN='/* BEGIN OMAFOX FIREFOX CHROME */'
CHROME_END='/* END OMAFOX FIREFOX CHROME */'

cleanup() {
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

assert_not_contains() {
  local needle=$1 target=$2
  if grep -Fq "$needle" "$target"; then
    echo "unexpected text in $target: $needle" >&2
    exit 1
  fi
}

mkdir -p \
  "$TEST_HOME" "$MOCK_BIN" "$THEME_DIR" "$FIREFOX_ROOT" \
  "$RELATIVE_PROFILE/chrome" "$ABSOLUTE_PROFILE" "$(dirname "$NATIVE_HOST")"
install -m 755 "$TEST_DIR/fixtures/bin/omarchy" "$MOCK_BIN/omarchy"
install -m 755 "$PROJECT_DIR/packaging/omafox-hook" "$HOOK_SOURCE"
install -m 755 /dev/null "$NATIVE_HOST"
install -m 644 "$PROJECT_DIR/packaging/org.omarchy.omafox.json" "$NATIVE_MANIFEST"
cp "$TEST_DIR/fixtures/colors.toml" "$THEME_DIR/colors.toml"
printf '%s\n' 'osaka-jade' > "$THEME_DIR/theme.name"

cat > "$FIREFOX_ROOT/profiles.ini" <<EOF
[Profile0]
Name=default-release
IsRelative=1
Path=abc123.default-release

[Profile1]
Name=external
IsRelative=0
Path=$ABSOLUTE_PROFILE

[Profile2]
Name=duplicate
IsRelative=1
Path=abc123.default-release

[Profile3]
Name=missing
IsRelative=1
Path=missing.default
EOF

printf '%s\n' 'user_pref("example.existing", true);' > "$RELATIVE_PROFILE/user.js"
chmod 640 "$RELATIVE_PROFILE/user.js"
cp "$RELATIVE_PROFILE/user.js" "$TEST_ROOT/original-user.js"

printf '%s\n' '#TabsToolbar { color: red; }' > "$RELATIVE_PROFILE/chrome/userChrome.css"
chmod 640 "$RELATIVE_PROFILE/chrome/userChrome.css"
cp "$RELATIVE_PROFILE/chrome/userChrome.css" "$TEST_ROOT/original-userChrome.css"

export HOME="$TEST_HOME"
export PATH="$MOCK_BIN:$PATH"
export OMAFOX_THEME_DIR="$THEME_DIR"
export OMAFOX_THEME_NAME_FILE="$THEME_DIR/theme.name"
export OMAFOX_NATIVE_HOST_PATH="$NATIVE_HOST"
export OMAFOX_NATIVE_MANIFEST_PATH="$NATIVE_MANIFEST"
export OMAFOX_HOOK_SOURCE="$HOOK_SOURCE"
export OMAFOX_FIREFOX_ROOT="$FIREFOX_ROOT"
export OMAFOX_FIREFOX_PROFILES_FILE="$FIREFOX_ROOT/profiles.ini"

initial_status=$("$PROJECT_DIR/omarchy/omafox" status)
[[ $initial_status == *"Firefox profile: $RELATIVE_PROFILE (not configured)"* ]]
[[ $initial_status == *"Firefox profile: $ABSOLUTE_PROFILE (not configured)"* ]]
[[ $initial_status == *"Firefox profile: $MISSING_PROFILE (missing)"* ]]

setup_output=$("$PROJECT_DIR/omarchy/omafox" setup 2>&1)
[[ $(grep -Fc "Configured Firefox profile: $RELATIVE_PROFILE" <<< "$setup_output") == 1 ]]
[[ $(grep -Fc "Configured Firefox profile: $ABSOLUTE_PROFILE" <<< "$setup_output") == 1 ]]
[[ $setup_output == *"Skipped missing Firefox profile: $MISSING_PROFILE"* ]]
[[ $setup_output == *"Restart Firefox once"* ]]

for profile in "$RELATIVE_PROFILE" "$ABSOLUTE_PROFILE"; do
  css="$profile/chrome/omafox-blank-page.css"
  [[ $(sed -n '1p' "$css") == "$BLANK_MARKER" ]]
  grep -Fq '@-moz-document url("about:newtab")' "$css"
  grep -Fq '@media not -moz-pref("browser.newtabpage.enabled")' "$css"
  grep -Fq '@-moz-document url("chrome://browser/content/blanktab.html")' "$css"
  [[ $(grep -Fc 'background-color: #111c18 !important;' "$css") == 2 ]]
  grep -Fq 'color-scheme: dark !important;' "$css"
  [[ $(stat -c '%a' "$css") == 600 ]]
  [[ $(grep -Fxc "$CHROME_BEGIN" "$profile/chrome/userChrome.css") == 1 ]]
  [[ $(grep -Fxc "$CHROME_END" "$profile/chrome/userChrome.css") == 1 ]]
  [[ $(grep -Fxc '@media not -moz-pref("browser.newtabpage.enabled") {' "$profile/chrome/userChrome.css") == 1 ]]
  [[ $(grep -Fxc '  :root:not([privatebrowsingmode="temporary"]) {' "$profile/chrome/userChrome.css") == 1 ]]
  [[ $(grep -Fxc '    --tabpanel-background-color: var(--lwt-accent-color) !important;' "$profile/chrome/userChrome.css") == 1 ]]
  [[ $(grep -Fxc '  border-block-start-width: 0.01px !important;' "$profile/chrome/userChrome.css") == 1 ]]
  grep -Fqx '  border-block-start-color: var(--tabs-navbar-separator-color) !important;' \
    "$profile/chrome/userChrome.css"
  [[ $(grep -Fxc "$CSS_BEGIN" "$profile/chrome/userContent.css") == 1 ]]
  [[ $(grep -Fxc "$CSS_END" "$profile/chrome/userContent.css") == 1 ]]
  [[ $(grep -Fxc '@import url("omafox-blank-page.css");' "$profile/chrome/userContent.css") == 1 ]]
  [[ $(grep -Fxc "$PREFS_BEGIN" "$profile/user.js") == 1 ]]
  [[ $(grep -Fxc "$PREFS_END" "$profile/user.js") == 1 ]]
  [[ $(grep -Fxc 'user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);' "$profile/user.js") == 1 ]]
done

[[ $(stat -c '%a' "$RELATIVE_PROFILE/user.js") == 640 ]]
[[ $(stat -c '%a' "$RELATIVE_PROFILE/chrome/userChrome.css") == 640 ]]
[[ $(stat -c '%a' "$ABSOLUTE_PROFILE/chrome") == 700 ]]
[[ $(stat -c '%a' "$ABSOLUTE_PROFILE/user.js") == 600 ]]
[[ $(stat -c '%a' "$ABSOLUTE_PROFILE/chrome/userChrome.css") == 600 ]]
grep -Fqx 'user_pref("example.existing", true);' "$RELATIVE_PROFILE/user.js"
grep -Fqx '#TabsToolbar { color: red; }' "$RELATIVE_PROFILE/chrome/userChrome.css"

configured_status=$("$PROJECT_DIR/omarchy/omafox" status)
[[ $configured_status == *"Firefox profile: $RELATIVE_PROFILE (configured)"* ]]
[[ $configured_status == *"Firefox profile: $ABSOLUTE_PROFILE (configured)"* ]]

# A theme change regenerates the blank page color for configured profiles only.
sed -i 's/^background = .*/background = "#222233"/' "$THEME_DIR/colors.toml"
"$PROJECT_DIR/omarchy/omafox" sync >/dev/null
grep -Fq 'background-color: #222233 !important;' "$RELATIVE_PROFILE/chrome/omafox-blank-page.css"
grep -Fq 'background-color: #222233 !important;' "$ABSOLUTE_PROFILE/chrome/omafox-blank-page.css"

# Setup is idempotent.
"$PROJECT_DIR/omarchy/omafox" setup >/dev/null 2>&1
[[ $(grep -Fxc "$CHROME_BEGIN" "$RELATIVE_PROFILE/chrome/userChrome.css") == 1 ]]
[[ $(grep -Fxc "$CSS_BEGIN" "$RELATIVE_PROFILE/chrome/userContent.css") == 1 ]]
[[ $(grep -Fxc "$PREFS_BEGIN" "$RELATIVE_PROFILE/user.js") == 1 ]]

# An unmanaged blank page stylesheet is never overwritten.
printf '%s\n' '/* user file */' > "$ABSOLUTE_PROFILE/chrome/omafox-blank-page.css"
conflict_status=$("$PROJECT_DIR/omarchy/omafox" status)
[[ $conflict_status == *"Firefox profile: $ABSOLUTE_PROFILE (conflict)"* ]]
if remove_error=$("$PROJECT_DIR/omarchy/omafox" remove 2>&1); then
  echo "remove with an unmanaged blank page stylesheet unexpectedly succeeded" >&2
  exit 1
fi
[[ $remove_error == *"refusing to modify unmanaged Firefox blank page stylesheet"* ]]
grep -Fqx '/* user file */' "$ABSOLUTE_PROFILE/chrome/omafox-blank-page.css"
rm -f "$ABSOLUTE_PROFILE/chrome/omafox-blank-page.css"

"$PROJECT_DIR/omarchy/omafox" remove >/dev/null
for profile in "$RELATIVE_PROFILE" "$ABSOLUTE_PROFILE"; do
  [[ ! -e $profile/chrome/omafox-blank-page.css ]]
  [[ ! -e $profile/chrome/userContent.css ]]
  if [[ -f $profile/user.js ]]; then
    assert_not_contains "$PREFS_BEGIN" "$profile/user.js"
  fi
  if [[ -f $profile/chrome/userChrome.css ]]; then
    assert_not_contains "$CHROME_BEGIN" "$profile/chrome/userChrome.css"
  fi
done
cmp "$TEST_ROOT/original-user.js" "$RELATIVE_PROFILE/user.js"
cmp "$TEST_ROOT/original-userChrome.css" "$RELATIVE_PROFILE/chrome/userChrome.css"
[[ ! -e $ABSOLUTE_PROFILE/chrome/userChrome.css ]]

echo "firefox-integration.test.sh: ok"
