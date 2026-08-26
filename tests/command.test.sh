#!/bin/bash

set -euo pipefail

TEST_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_DIR=$(dirname "$TEST_DIR")
TEST_ROOT=$(mktemp -d)
TEST_HOME="$TEST_ROOT/home"
MOCK_BIN="$TEST_ROOT/bin"
THEME_DIR="$TEST_ROOT/theme"
STATE_FILE="$TEST_HOME/.local/state/omafox/theme.json"

cleanup() {
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

mkdir -p "$TEST_HOME" "$MOCK_BIN" "$THEME_DIR"

install -m 755 "$TEST_DIR/fixtures/bin/omarchy" "$MOCK_BIN/omarchy"
cp "$TEST_DIR/fixtures/colors.toml" "$THEME_DIR/colors.toml"
printf '%s\n' 'osaka-jade' > "$THEME_DIR/theme.name"

export HOME="$TEST_HOME"
export PATH="$MOCK_BIN:$PATH"
export OMAFOX_THEME_DIR="$THEME_DIR"
export OMAFOX_THEME_NAME_FILE="$THEME_DIR/theme.name"

[[ $("$PROJECT_DIR/omarchy/omafox" version) == 1.1.0 ]]
help_output=$("$PROJECT_DIR/omarchy/omafox" help)
expected_commands=$'Commands:\n  sync     Queue the current palette for connected browsers\n  payload  Print the current JSON protocol message\n  status   Show the current theme and integration state\n  setup    Enable the packaged Omafox integration for this user\n  remove   Remove this user\'s Omafox hook and theme state\n  version  Print the Omafox version\n  help     Show this help'
[[ $help_output == *"$expected_commands"* ]]

if unknown_error=$("$PROJECT_DIR/omarchy/omafox" unknown-command 2>&1); then
  echo "unknown command unexpectedly succeeded" >&2
  exit 1
fi
[[ $unknown_error == *"unknown command: unknown-command"* ]]

for command in sync payload status; do
  if argument_error=$("$PROJECT_DIR/omarchy/omafox" "$command" unexpected 2>&1); then
    echo "$command unexpectedly accepted an argument" >&2
    exit 1
  fi
  [[ $argument_error == *"does not accept arguments"* ]]
done

payload=$("$PROJECT_DIR/omarchy/omafox" payload)
python3 - "$payload" <<'PY'
import json
import sys

message = json.loads(sys.argv[1])
assert message["protocol"] == "omafox"
assert message["version"] == 1
assert message["action"] == "theme-set"
assert message["theme"] == "osaka-jade"
assert message["palette"]["accent"] == "#509475"
assert len(message["palette"]) == 26
PY

special_theme=$'quoted "theme"\\path'
printf '%s\n' "$special_theme" > "$THEME_DIR/theme.name"
escaped_payload=$("$PROJECT_DIR/omarchy/omafox" payload)
python3 - "$escaped_payload" "$special_theme" <<'PY'
import json
import sys

assert json.loads(sys.argv[1])["theme"] == sys.argv[2]
PY

printf -v long_theme '%101s' ''
long_theme=${long_theme// /x}
printf '%s\n' "$long_theme" > "$THEME_DIR/theme.name"
if long_theme_error=$("$PROJECT_DIR/omarchy/omafox" payload 2>&1); then
  echo "overlong theme name unexpectedly succeeded" >&2
  exit 1
fi
[[ $long_theme_error == *"theme name exceeds 100 characters"* ]]
printf '%s\n' 'osaka-jade' > "$THEME_DIR/theme.name"

# Every individual Quattro field may be omitted without aborting the sync.
for omitted_key in mode accent selection muted background dark_background darker_background \
  lighter_background foreground dark_foreground light_foreground bright_foreground \
  red yellow orange green cyan blue magenta brown bright_red bright_yellow bright_green \
  bright_cyan bright_blue bright_magenta; do
  sed -E "/^${omitted_key}[[:space:]]*=/d" \
    "$TEST_DIR/fixtures/colors.toml" > "$THEME_DIR/colors.toml"
  "$PROJECT_DIR/omarchy/omafox" payload >/dev/null
done

# Some stock Quattro themes omit orange and brown. Verify the command derives
# both values while still producing the extension's complete JSON schema.
sed -E '/^(orange|brown)[[:space:]]*=/d' \
  "$TEST_DIR/fixtures/colors.toml" > "$THEME_DIR/colors.toml"
fallback_payload=$("$PROJECT_DIR/omarchy/omafox" payload)
python3 - "$fallback_payload" <<'PY'
import json
import sys

palette = json.loads(sys.argv[1])["palette"]
assert palette["orange"] == "#459451"
assert palette["brown"] == "#53685B"
PY

sed -E 's/^accent[[:space:]]*=.*/accent = "not-a-color"/' \
  "$TEST_DIR/fixtures/colors.toml" > "$THEME_DIR/colors.toml"
malformed_payload=$("$PROJECT_DIR/omarchy/omafox" payload)
python3 - "$malformed_payload" <<'PY'
import json
import sys

assert json.loads(sys.argv[1])["palette"]["accent"] == "#509475"
PY

# A minimal custom palette should infer light mode, normalize shorthand/0x
# colors, and generate valid values for every omitted Firefox input.
cp "$TEST_DIR/fixtures/minimal-colors.toml" "$THEME_DIR/colors.toml"
minimal_payload=$("$PROJECT_DIR/omarchy/omafox" payload)
python3 - "$minimal_payload" <<'PY'
import json
import re
import sys

message = json.loads(sys.argv[1])
palette = message["palette"]
assert message["theme"] == "osaka-jade"
assert palette["mode"] == "light"
assert palette["accent"] == "#112233"
assert palette["background"] == "#FAFAFA"
assert palette["foreground"] == "#101010"
assert len(palette) == 26
for key, value in palette.items():
    if key != "mode":
        assert re.fullmatch(r"#[0-9a-fA-F]{6}", value), (key, value)
PY

"$PROJECT_DIR/omarchy/omafox" sync
[[ -f $STATE_FILE ]]
[[ $(stat -c '%a' "$(dirname "$STATE_FILE")") == 700 ]]
[[ $(stat -c '%a' "$STATE_FILE") == 600 ]]
python3 - "$STATE_FILE" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    message = json.load(source)

assert message["protocol"] == "omafox"
assert message["version"] == 1
assert message["action"] == "theme-set"
assert message["theme"] == "osaka-jade"
assert message["palette"]["mode"] == "light"
PY

export OMAFOX_NATIVE_HOST_PATH="$TEST_ROOT/missing/omafox-native-host"
export OMAFOX_NATIVE_MANIFEST_PATH="$TEST_ROOT/missing/org.omarchy.omafox.json"
export OMAFOX_HOOK_SOURCE="$TEST_ROOT/missing/omafox-hook"
if setup_error=$("$PROJECT_DIR/omarchy/omafox" setup 2>&1); then
  echo "setup without packaged files unexpectedly succeeded" >&2
  exit 1
fi
[[ $setup_error == *"packaged native host not found"* ]]

"$PROJECT_DIR/omarchy/omafox" remove >/dev/null
[[ ! -e $STATE_FILE ]]
[[ ! -d "$TEST_HOME/.local/state/omafox" ]]

echo "command.test.sh: ok"
