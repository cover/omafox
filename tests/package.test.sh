#!/bin/bash

set -euo pipefail

TEST_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_DIR=$(dirname "$TEST_DIR")
TEST_ROOT=$(mktemp -d)
PACKAGE_ROOT="$TEST_ROOT/package"
TEST_HOME="$TEST_ROOT/home"
MOCK_BIN="$TEST_ROOT/bin"
THEME_DIR="$TEST_ROOT/theme"
BUILD_DIR="$TEST_ROOT/build"
SYSTEM_COMMAND="$PACKAGE_ROOT/usr/bin/omafox"
SYSTEM_HOST="$PACKAGE_ROOT/usr/lib/omafox/omafox-native-host"
SYSTEM_MANIFEST="$PACKAGE_ROOT/usr/lib/mozilla/native-messaging-hosts/org.omarchy.omafox.json"
SYSTEM_HOOK_SOURCE="$PACKAGE_ROOT/usr/share/omafox/hooks/omafox"

cleanup() {
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

mkdir -p "$TEST_HOME" "$MOCK_BIN" "$THEME_DIR"
install -m 755 "$TEST_DIR/fixtures/bin/omarchy" "$MOCK_BIN/omarchy"
cp "$TEST_DIR/fixtures/colors.toml" "$THEME_DIR/colors.toml"
printf '%s\n' 'osaka-jade' > "$THEME_DIR/theme.name"

make -C "$PROJECT_DIR" BUILD_DIR="$BUILD_DIR" all >/dev/null
make -C "$PROJECT_DIR" \
  BUILD_DIR="$BUILD_DIR" \
  DESTDIR="$PACKAGE_ROOT" \
  PREFIX=/usr \
  install >/dev/null

[[ -x $SYSTEM_COMMAND ]]
[[ -x $SYSTEM_HOST ]]
[[ -f $SYSTEM_MANIFEST ]]
[[ -x $SYSTEM_HOOK_SOURCE ]]
[[ -f "$PACKAGE_ROOT/usr/share/doc/omafox/README.md" ]]
[[ -f "$PACKAGE_ROOT/usr/share/licenses/omafox/LICENSE" ]]
[[ $($SYSTEM_COMMAND version) == 1.0.0 ]]

python3 - "$SYSTEM_MANIFEST" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    manifest = json.load(source)

assert manifest["name"] == "org.omarchy.omafox"
assert manifest["path"] == "/usr/lib/omafox/omafox-native-host"
assert manifest["type"] == "stdio"
assert manifest["allowed_extensions"] == ["@omafox"]
PY

export HOME="$TEST_HOME"
export PATH="$MOCK_BIN:$PATH"
export OMAFOX_NATIVE_HOST_PATH="$SYSTEM_HOST"
export OMAFOX_NATIVE_MANIFEST_PATH="$SYSTEM_MANIFEST"
export OMAFOX_HOOK_SOURCE="$SYSTEM_HOOK_SOURCE"
export OMAFOX_THEME_DIR="$THEME_DIR"
export OMAFOX_THEME_NAME_FILE="$THEME_DIR/theme.name"

"$SYSTEM_COMMAND" setup >/dev/null
USER_HOOK="$TEST_HOME/.config/omarchy/hooks/theme-set.d/omafox"
STATE_FILE="$TEST_HOME/.local/state/omafox/theme.json"
[[ -x $USER_HOOK ]]
cmp "$SYSTEM_HOOK_SOURCE" "$USER_HOOK"
[[ -f $STATE_FILE ]]
python3 - "$STATE_FILE" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    message = json.load(source)

assert message["protocol"] == "omafox"
assert message["version"] == 1
assert message["action"] == "theme-set"
assert message["theme"] == "osaka-jade"
assert message["palette"]["mode"] == "dark"
PY
status_output=$("$SYSTEM_COMMAND" status)
[[ $status_output == *"Native host: $SYSTEM_HOST (installed)"* ]]

"$SYSTEM_COMMAND" remove >/dev/null
[[ ! -e $USER_HOOK ]]
[[ ! -e $STATE_FILE ]]
[[ ! -d "$TEST_HOME/.local/state/omafox" ]]
[[ -x $SYSTEM_COMMAND ]]
[[ -x $SYSTEM_HOST ]]
[[ -f $SYSTEM_MANIFEST ]]

echo "package.test.sh: ok"
