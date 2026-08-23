"use strict";

const assert = require("node:assert/strict");
const {
  ACTION,
  COLOR_KEYS,
  PALETTE_KEYS,
  PROTOCOL,
  parseThemeMessage,
  toFirefoxTheme
} = require("../extension/theme.js");

const palette = {
  mode: "dark",
  accent: "#509475",
  selection: "#32473B",
  muted: "#53685B",
  background: "#111c18",
  dark_background: "#0c1512",
  darker_background: "#090f0d",
  lighter_background: "#23372B",
  foreground: "#C1C497",
  dark_foreground: "#81B8A8",
  light_foreground: "#D6D5BC",
  bright_foreground: "#F7E8B2",
  red: "#FF5345",
  yellow: "#459451",
  orange: "#a2734b",
  green: "#549e6a",
  cyan: "#2DD5B7",
  blue: "#509475",
  magenta: "#D2689C",
  brown: "#513925",
  bright_red: "#db9f9c",
  bright_yellow: "#E5C736",
  bright_green: "#63b07a",
  bright_cyan: "#8CD3CB",
  bright_blue: "#ACD4CF",
  bright_magenta: "#75bbb3"
};

const message = {
  protocol: PROTOCOL,
  version: 1,
  action: ACTION,
  theme: "osaka-jade",
  palette
};
const record = parseThemeMessage(message);

assert.equal(PALETTE_KEYS.length, 26);
assert.equal(COLOR_KEYS.length, 25);
assert.equal(record.themeName, "osaka-jade");
assert.deepEqual(record.palette, palette);

const firefoxTheme = toFirefoxTheme(record);
assert.equal(firefoxTheme.colors.frame, palette.background);
assert.equal(firefoxTheme.colors.tab_line, palette.accent);
assert.equal(firefoxTheme.colors.toolbar_field_highlight, palette.selection);
assert.equal(firefoxTheme.colors.toolbar_field_highlight_text, palette.bright_foreground);
assert.equal(firefoxTheme.colors.button_background_active, palette.selection);
assert.equal(firefoxTheme.colors.popup_highlight, palette.selection);
assert.equal(firefoxTheme.colors.sidebar_highlight, palette.selection);
assert.equal(firefoxTheme.colors.toolbar_bottom_separator, palette.brown);
assert.equal(firefoxTheme.properties.color_scheme, "dark");

const lowContrastHighlightTheme = toFirefoxTheme({
  ...record,
  palette: {
    ...palette,
    selection: "#FDFAFA",
    bright_foreground: "#FEFBFB"
  }
});
assert.equal(lowContrastHighlightTheme.colors.toolbar_field_highlight_text, palette.background);

const lowContrastIconTheme = toFirefoxTheme({
  ...record,
  palette: {
    ...palette,
    accent: "#AE6378",
    selection: "#FDFAFA",
    foreground: "#FDFAFA",
    light_foreground: "#FDFBFB",
    bright_foreground: "#FEFBFB",
    bright_yellow: "#FFD384"
  }
});
assert.equal(lowContrastIconTheme.colors.icons, "#FDFBFB");
assert.equal(lowContrastIconTheme.colors.button_background_active, "#AE6378");
assert.equal(lowContrastIconTheme.colors.popup_highlight, "#AE6378");
assert.equal(lowContrastIconTheme.colors.sidebar_highlight, "#AE6378");

const monochromePalette = Object.fromEntries(
  PALETTE_KEYS.map((key) => [key, key === "mode" ? "dark" : "#777777"])
);
const fallbackHighlightTheme = toFirefoxTheme({ ...record, palette: monochromePalette });
assert.equal(fallbackHighlightTheme.colors.toolbar_field_highlight_text, "#000000");

assert.throws(
  () => parseThemeMessage({
    ...message,
    palette: { ...palette, accent: "red" }
  }),
  /accent/
);
assert.throws(
  () => parseThemeMessage({ ...message, protocol: "other" }),
  /protocol/
);
assert.throws(
  () => parseThemeMessage({ ...message, extra: "nope" }),
  /Unexpected message/
);
assert.throws(
  () => parseThemeMessage({ ...message, theme: "x".repeat(101) }),
  /theme name/
);
assert.throws(
  () => parseThemeMessage({
    ...message,
    palette: { ...palette, extra: "#123456" }
  }),
  /Unexpected palette/
);

console.log("theme.test.js: ok");
