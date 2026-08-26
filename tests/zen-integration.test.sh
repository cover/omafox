#!/bin/bash

set -euo pipefail

TEST_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_DIR=$(dirname "$TEST_DIR")
TEST_ROOT=$(mktemp -d)
TEST_HOME="$TEST_ROOT/home"
MOCK_BIN="$TEST_ROOT/bin"
THEME_DIR="$TEST_ROOT/theme"
ZEN_ROOT="$TEST_HOME/.config/zen"
RELATIVE_PROFILE="$ZEN_ROOT/Profiles/default-release"
ABSOLUTE_PROFILE="$TEST_ROOT/external Zen profile"
MISSING_PROFILE="$ZEN_ROOT/Profiles/missing"
NATIVE_HOST="$TEST_ROOT/package/omafox-native-host"
NATIVE_MANIFEST="$TEST_ROOT/package/org.omarchy.omafox.json"
HOOK_SOURCE="$TEST_ROOT/package/omafox-hook"
ZEN_BRIDGE_SOURCE="$TEST_ROOT/package/omafox.css"
ZEN_BRIDGE_MARKER='/* OMAFOX ZEN BRIDGE MANAGED FILE */'
CSS_BEGIN='/* BEGIN OMAFOX ZEN BRIDGE */'
CSS_END='/* END OMAFOX ZEN BRIDGE */'
PREFS_BEGIN='// BEGIN OMAFOX ZEN BRIDGE'
PREFS_END='// END OMAFOX ZEN BRIDGE'

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
  "$TEST_HOME" "$MOCK_BIN" "$THEME_DIR" "$ZEN_ROOT" \
  "$RELATIVE_PROFILE/chrome" "$ABSOLUTE_PROFILE" "$(dirname "$NATIVE_HOST")"
install -m 755 "$TEST_DIR/fixtures/bin/omarchy" "$MOCK_BIN/omarchy"
install -m 755 "$PROJECT_DIR/packaging/omafox-hook" "$HOOK_SOURCE"
install -m 755 /dev/null "$NATIVE_HOST"
install -m 644 "$PROJECT_DIR/packaging/org.omarchy.omafox.json" "$NATIVE_MANIFEST"
install -m 644 "$PROJECT_DIR/packaging/zen/omafox.css" "$ZEN_BRIDGE_SOURCE"
cp "$TEST_DIR/fixtures/colors.toml" "$THEME_DIR/colors.toml"
printf '%s\n' 'osaka-jade' > "$THEME_DIR/theme.name"

cat > "$ZEN_ROOT/profiles.ini" <<EOF
[Profile0]
Name=default-release
IsRelative=1
Path=Profiles/default-release

[Profile1]
Name=external
IsRelative=0
Path=$ABSOLUTE_PROFILE

[Profile2]
Name=duplicate
IsRelative=1
Path=Profiles/default-release

[Profile3]
Name=missing
IsRelative=1
Path=Profiles/missing
EOF

printf '%s\n' '@namespace url("http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul");' > \
  "$RELATIVE_PROFILE/chrome/userChrome.css"
printf '%s\n' 'user_pref("example.existing", true);' > "$RELATIVE_PROFILE/user.js"
chmod 640 "$RELATIVE_PROFILE/chrome/userChrome.css"
chmod 604 "$RELATIVE_PROFILE/user.js"
cp "$RELATIVE_PROFILE/chrome/userChrome.css" "$TEST_ROOT/original-userChrome.css"
cp "$RELATIVE_PROFILE/user.js" "$TEST_ROOT/original-user.js"

export HOME="$TEST_HOME"
export PATH="$MOCK_BIN:$PATH"
export OMAFOX_THEME_DIR="$THEME_DIR"
export OMAFOX_THEME_NAME_FILE="$THEME_DIR/theme.name"
export OMAFOX_NATIVE_HOST_PATH="$NATIVE_HOST"
export OMAFOX_NATIVE_MANIFEST_PATH="$NATIVE_MANIFEST"
export OMAFOX_HOOK_SOURCE="$HOOK_SOURCE"
export OMAFOX_ZEN_ROOT="$ZEN_ROOT"
export OMAFOX_ZEN_BRIDGE_SOURCE="$ZEN_BRIDGE_SOURCE"

[[ $(sed -n '1p' "$ZEN_BRIDGE_SOURCE") == "$ZEN_BRIDGE_MARKER" ]]
grep -Fq ':root[lwtheme] {' "$ZEN_BRIDGE_SOURCE"
grep -Fq ':root[lwtheme] #zen-main-app-wrapper {' "$ZEN_BRIDGE_SOURCE"
grep -Fq ':root[lwtheme] #zen-toolbar-background {' "$ZEN_BRIDGE_SOURCE"
grep -Fq -- '--zen-main-browser-background:' "$ZEN_BRIDGE_SOURCE"
grep -Fq -- '--zen-primary-color:' "$ZEN_BRIDGE_SOURCE"

# Unrelated profile customizations alone are not an incomplete Omafox setup.
initial_status=$("$PROJECT_DIR/omarchy/omafox" status)
[[ $initial_status == *"Zen profile: $RELATIVE_PROFILE (not configured)"* ]]
[[ $initial_status == *"Zen profile: $ABSOLUTE_PROFILE (not configured)"* ]]
[[ $initial_status == *"Zen profile: $MISSING_PROFILE (missing)"* ]]

setup_output=$("$PROJECT_DIR/omarchy/omafox" setup 2>&1)
[[ $(grep -Fc "Configured Zen profile: $RELATIVE_PROFILE" <<< "$setup_output") == 1 ]]
[[ $(grep -Fc "Configured Zen profile: $ABSOLUTE_PROFILE" <<< "$setup_output") == 1 ]]
[[ $setup_output == *"Skipped missing Zen profile: $MISSING_PROFILE"* ]]
[[ $setup_output == *"Restart Zen Browser once"* ]]

for profile in "$RELATIVE_PROFILE" "$ABSOLUTE_PROFILE"; do
  cmp "$ZEN_BRIDGE_SOURCE" "$profile/chrome/omafox.css"
  [[ $(grep -Fxc "$CSS_BEGIN" "$profile/chrome/userChrome.css") == 1 ]]
  [[ $(grep -Fxc "$CSS_END" "$profile/chrome/userChrome.css") == 1 ]]
  [[ $(grep -Fxc '@import url("omafox.css");' "$profile/chrome/userChrome.css") == 1 ]]
  [[ $(grep -Fxc "$PREFS_BEGIN" "$profile/user.js") == 1 ]]
  [[ $(grep -Fxc "$PREFS_END" "$profile/user.js") == 1 ]]
  [[ $(grep -Fxc 'user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);' "$profile/user.js") == 1 ]]
  [[ $(grep -Fxc 'user_pref("zen.theme.disable-lightweight", false);' "$profile/user.js") == 1 ]]
  [[ $(sed -n '1p' "$profile/chrome/userChrome.css") == "$CSS_BEGIN" ]]
  [[ $(stat -c '%a' "$profile/chrome/omafox.css") == 600 ]]
done

[[ $(stat -c '%a' "$RELATIVE_PROFILE/chrome/userChrome.css") == 640 ]]
[[ $(stat -c '%a' "$RELATIVE_PROFILE/user.js") == 604 ]]
[[ $(stat -c '%a' "$ABSOLUTE_PROFILE/chrome") == 700 ]]
[[ $(stat -c '%a' "$ABSOLUTE_PROFILE/chrome/userChrome.css") == 600 ]]
[[ $(stat -c '%a' "$ABSOLUTE_PROFILE/user.js") == 600 ]]
grep -Fqx '@namespace url("http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul");' \
  "$RELATIVE_PROFILE/chrome/userChrome.css"
grep -Fqx 'user_pref("example.existing", true);' "$RELATIVE_PROFILE/user.js"

configured_status=$("$PROJECT_DIR/omarchy/omafox" status)
[[ $configured_status == *"Zen profile: $RELATIVE_PROFILE (configured)"* ]]
[[ $configured_status == *"Zen profile: $ABSOLUTE_PROFILE (configured)"* ]]

# Setup is idempotent and refreshes a stale packaged bridge.
"$PROJECT_DIR/omarchy/omafox" setup >/dev/null 2>&1
[[ $(grep -Fxc "$CSS_BEGIN" "$RELATIVE_PROFILE/chrome/userChrome.css") == 1 ]]
[[ $(grep -Fxc "$PREFS_BEGIN" "$RELATIVE_PROFILE/user.js") == 1 ]]
printf '%s\n' '/* package update */' >> "$ZEN_BRIDGE_SOURCE"
outdated_status=$("$PROJECT_DIR/omarchy/omafox" status)
[[ $outdated_status == *"Zen profile: $RELATIVE_PROFILE (outdated)"* ]]
"$PROJECT_DIR/omarchy/omafox" setup >/dev/null 2>&1
cmp "$ZEN_BRIDGE_SOURCE" "$RELATIVE_PROFILE/chrome/omafox.css"

# Removal preflights every profile and refuses to delete an unowned collision.
printf '%s\n' '/* existing user file */' > "$ABSOLUTE_PROFILE/chrome/omafox.css"
conflict_status=$("$PROJECT_DIR/omarchy/omafox" status)
[[ $conflict_status == *"Zen profile: $ABSOLUTE_PROFILE (conflict)"* ]]
if remove_error=$("$PROJECT_DIR/omarchy/omafox" remove 2>&1); then
  echo "remove with an unmanaged Zen bridge unexpectedly succeeded" >&2
  exit 1
fi
[[ $remove_error == *"refusing to modify unmanaged Zen bridge"* ]]
grep -Fqx "$CSS_BEGIN" "$RELATIVE_PROFILE/chrome/userChrome.css"
grep -Fqx "$PREFS_BEGIN" "$RELATIVE_PROFILE/user.js"
grep -Fqx '/* existing user file */' "$ABSOLUTE_PROFILE/chrome/omafox.css"
install -m 600 "$ZEN_BRIDGE_SOURCE" "$ABSOLUTE_PROFILE/chrome/omafox.css"

"$PROJECT_DIR/omarchy/omafox" remove >/dev/null
for profile in "$RELATIVE_PROFILE" "$ABSOLUTE_PROFILE"; do
  [[ ! -e $profile/chrome/omafox.css ]]
  if [[ -f $profile/chrome/userChrome.css ]]; then
    assert_not_contains "$CSS_BEGIN" "$profile/chrome/userChrome.css"
  fi
  if [[ -f $profile/user.js ]]; then
    assert_not_contains "$PREFS_BEGIN" "$profile/user.js"
  fi
done
cmp "$TEST_ROOT/original-userChrome.css" "$RELATIVE_PROFILE/chrome/userChrome.css"
cmp "$TEST_ROOT/original-user.js" "$RELATIVE_PROFILE/user.js"
[[ ! -e $ABSOLUTE_PROFILE/chrome/userChrome.css ]]
[[ ! -e $ABSOLUTE_PROFILE/user.js ]]

# Setup also refuses an unowned collision before changing any other profile.
printf '%s\n' '/* existing user file */' > "$ABSOLUTE_PROFILE/chrome/omafox.css"
if collision_error=$("$PROJECT_DIR/omarchy/omafox" setup 2>&1); then
  echo "setup with an unmanaged Zen bridge unexpectedly succeeded" >&2
  exit 1
fi
[[ $collision_error == *"refusing to modify unmanaged Zen bridge"* ]]
grep -Fqx '/* existing user file */' "$ABSOLUTE_PROFILE/chrome/omafox.css"
[[ ! -e $RELATIVE_PROFILE/chrome/omafox.css ]]
assert_not_contains "$CSS_BEGIN" "$RELATIVE_PROFILE/chrome/userChrome.css"
rm -f "$ABSOLUTE_PROFILE/chrome/omafox.css"

# A malformed managed block aborts before any detected profile is changed.
printf '%s\n' "$PREFS_BEGIN" > "$ABSOLUTE_PROFILE/user.js"
if malformed_error=$("$PROJECT_DIR/omarchy/omafox" setup 2>&1); then
  echo "setup with malformed Zen markers unexpectedly succeeded" >&2
  exit 1
fi
[[ $malformed_error == *"malformed Omafox markers"* ]]
[[ ! -e $RELATIVE_PROFILE/chrome/omafox.css ]]
assert_not_contains "$CSS_BEGIN" "$RELATIVE_PROFILE/chrome/userChrome.css"

echo "zen-integration.test.sh: ok"
