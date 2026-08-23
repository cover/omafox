"use strict";

(function defineOmafoxTheme(root) {
  const PROTOCOL = "omafox";
  const ACTION = "theme-set";
  const SCHEMA_VERSION = 1;
  const MAX_THEME_NAME_LENGTH = 100;
  const PALETTE_KEYS = Object.freeze([
    "mode",
    "accent",
    "selection",
    "muted",
    "background",
    "dark_background",
    "darker_background",
    "lighter_background",
    "foreground",
    "dark_foreground",
    "light_foreground",
    "bright_foreground",
    "red",
    "yellow",
    "orange",
    "green",
    "cyan",
    "blue",
    "magenta",
    "brown",
    "bright_red",
    "bright_yellow",
    "bright_green",
    "bright_cyan",
    "bright_blue",
    "bright_magenta"
  ]);

  const COLOR_KEYS = Object.freeze(PALETTE_KEYS.filter((key) => key !== "mode"));
  const HEX_COLOR = /^#[0-9a-fA-F]{6}$/;
  const MIN_TEXT_CONTRAST = 4.5;

  function relativeLuminance(color) {
    const channels = [1, 3, 5].map((offset) => {
      const channel = Number.parseInt(color.slice(offset, offset + 2), 16) / 255;
      return channel <= 0.04045
        ? channel / 12.92
        : ((channel + 0.055) / 1.055) ** 2.4;
    });

    return (0.2126 * channels[0]) + (0.7152 * channels[1]) + (0.0722 * channels[2]);
  }

  function contrastRatio(first, second) {
    const firstLuminance = relativeLuminance(first);
    const secondLuminance = relativeLuminance(second);
    const lighter = Math.max(firstLuminance, secondLuminance);
    const darker = Math.min(firstLuminance, secondLuminance);
    return (lighter + 0.05) / (darker + 0.05);
  }

  function readableTextColor(background, preferred, alternatives) {
    for (const candidate of [preferred, ...alternatives]) {
      if (contrastRatio(background, candidate) >= MIN_TEXT_CONTRAST) {
        return candidate;
      }
    }

    return contrastRatio(background, "#000000") >= contrastRatio(background, "#FFFFFF")
      ? "#000000"
      : "#FFFFFF";
  }

  function validatePalette(palette) {
    if (!palette || typeof palette !== "object" || Array.isArray(palette)) {
      throw new TypeError("Palette must be an object");
    }

    if (palette.mode !== "dark" && palette.mode !== "light") {
      throw new TypeError("Palette mode must be dark or light");
    }

    for (const key of COLOR_KEYS) {
      if (!HEX_COLOR.test(palette[key] || "")) {
        throw new TypeError(`Invalid or missing palette color: ${key}`);
      }
    }
    for (const key of Object.keys(palette)) {
      if (!PALETTE_KEYS.includes(key)) {
        throw new TypeError(`Unexpected palette value: ${key}`);
      }
    }

    return palette;
  }

  function parseThemeMessage(message) {
    if (!message || typeof message !== "object" || Array.isArray(message)) {
      throw new TypeError("Theme message must be an object");
    }
    if (message.protocol !== PROTOCOL) {
      throw new TypeError("Unsupported Omafox protocol");
    }
    if (message.version !== SCHEMA_VERSION) {
      throw new TypeError("Unsupported Omafox protocol version");
    }
    if (message.action !== ACTION) {
      throw new TypeError("Unsupported Omafox action");
    }
    if (typeof message.theme !== "string"
        || !message.theme
        || message.theme.length > MAX_THEME_NAME_LENGTH) {
      throw new TypeError("Invalid or missing theme name");
    }
    for (const key of Object.keys(message)) {
      if (!["protocol", "version", "action", "theme", "palette"].includes(key)) {
        throw new TypeError(`Unexpected message value: ${key}`);
      }
    }
    const palette = validatePalette(message.palette);

    return {
      schemaVersion: SCHEMA_VERSION,
      themeName: message.theme,
      palette: { ...palette },
      appliedAt: new Date().toISOString()
    };
  }

  function toFirefoxTheme(record) {
    if (!record || record.schemaVersion !== SCHEMA_VERSION) {
      throw new TypeError("Unsupported stored theme schema");
    }

    const color = validatePalette(record.palette);
    const highlightText = readableTextColor(color.selection, color.bright_foreground, [
      color.foreground,
      color.light_foreground,
      color.dark_foreground,
      color.background,
      color.dark_background,
      color.darker_background,
      color.lighter_background
    ]);
    return {
      colors: {
        frame: color.background,
        frame_inactive: color.dark_background,
        tab_background_text: color.foreground,
        tab_text: color.bright_foreground,
        tab_selected: color.lighter_background,
        tab_line: color.accent,
        tab_loading: color.bright_cyan,
        toolbar: color.dark_background,
        toolbar_text: color.foreground,
        toolbar_field: color.darker_background,
        toolbar_field_text: color.light_foreground,
        toolbar_field_focus: color.background,
        toolbar_field_text_focus: color.bright_foreground,
        toolbar_field_border: color.muted,
        toolbar_field_border_focus: color.bright_blue,
        toolbar_field_highlight: color.selection,
        toolbar_field_highlight_text: highlightText,
        button_background_hover: color.lighter_background,
        button_background_active: color.selection,
        icons: color.light_foreground,
        icons_attention: color.bright_yellow,
        bookmark_text: color.foreground,
        popup: color.dark_background,
        popup_text: color.foreground,
        popup_border: color.muted,
        popup_highlight: color.selection,
        popup_highlight_text: highlightText,
        sidebar: color.dark_background,
        sidebar_text: color.foreground,
        sidebar_border: color.muted,
        sidebar_highlight: color.selection,
        sidebar_highlight_text: highlightText,
        ntp_background: color.background,
        ntp_card_background: color.lighter_background,
        ntp_text: color.foreground,
        toolbar_top_separator: color.muted,
        toolbar_bottom_separator: color.brown,
        toolbar_vertical_separator: color.muted
      },
      properties: {
        color_scheme: color.mode,
        content_color_scheme: color.mode
      }
    };
  }

  const api = Object.freeze({
    ACTION,
    COLOR_KEYS,
    PALETTE_KEYS,
    PROTOCOL,
    SCHEMA_VERSION,
    parseThemeMessage,
    toFirefoxTheme,
    validatePalette
  });

  root.OmafoxTheme = api;
  if (typeof module !== "undefined" && module.exports) {
    module.exports = api;
  }
})(globalThis);
