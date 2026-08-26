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
  const MIN_ICON_CONTRAST = 3;
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

  function minimumContrast(background, foregrounds) {
    return Math.min(...foregrounds.map((foreground) => contrastRatio(background, foreground)));
  }

  function readableBackgroundColor(
    foregrounds,
    preferred,
    alternatives,
    requiredContrast = MIN_ICON_CONTRAST
  ) {
    const candidates = [preferred, ...alternatives];
    for (const candidate of candidates) {
      if (minimumContrast(candidate, foregrounds) >= requiredContrast) {
        return candidate;
      }
    }

    return [...candidates, "#000000", "#FFFFFF"].reduce((best, candidate) => (
      minimumContrast(candidate, foregrounds) > minimumContrast(best, foregrounds)
        ? candidate
        : best
    ));
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
    const chromeTextAlternatives = [
      color.light_foreground,
      color.bright_foreground,
      color.dark_foreground,
      color.background,
      color.darker_background,
      color.lighter_background
    ];
    const toolbarText = readableTextColor(
      color.dark_background,
      color.foreground,
      chromeTextAlternatives
    );
    const tabBackgroundText = readableTextColor(
      color.background,
      color.foreground,
      chromeTextAlternatives
    );
    const selectedTabText = readableTextColor(
      color.lighter_background,
      color.bright_foreground,
      [
        color.foreground,
        color.light_foreground,
        color.dark_foreground,
        color.background,
        color.dark_background,
        color.darker_background
      ]
    );
    const toolbarFieldText = readableTextColor(
      color.darker_background,
      color.light_foreground,
      chromeTextAlternatives
    );
    const toolbarFieldFocusText = readableTextColor(
      color.background,
      color.bright_foreground,
      chromeTextAlternatives
    );
    const highlightText = readableTextColor(color.selection, color.bright_foreground, [
      color.foreground,
      color.light_foreground,
      color.dark_foreground,
      color.background,
      color.dark_background,
      color.darker_background,
      color.lighter_background
    ]);
    const buttonBackgroundHover = readableBackgroundColor(
      [toolbarText],
      color.lighter_background,
      [
        color.accent,
        color.selection,
        color.muted,
        color.dark_background,
        color.background,
        color.darker_background
      ],
      MIN_TEXT_CONTRAST
    );
    const buttonBackgroundActive = readableBackgroundColor(
      [toolbarText],
      color.selection,
      [
        color.accent,
        color.muted,
        color.lighter_background,
        color.dark_background,
        color.background,
        color.darker_background
      ],
      MIN_TEXT_CONTRAST
    );
    const selectedRowBackground = readableBackgroundColor(
      [color.foreground],
      color.selection,
      [
        color.accent,
        color.muted,
        color.lighter_background,
        color.dark_background,
        color.background,
        color.darker_background
      ]
    );
    const selectedRowText = readableTextColor(
      selectedRowBackground,
      color.bright_foreground,
      [
        color.foreground,
        color.light_foreground,
        color.dark_foreground,
        color.background,
        color.dark_background,
        color.darker_background,
        color.lighter_background
      ]
    );
    return {
      colors: {
        frame: color.background,
        frame_inactive: color.dark_background,
        tab_background_text: tabBackgroundText,
        tab_text: selectedTabText,
        tab_selected: color.lighter_background,
        tab_line: color.accent,
        tab_loading: color.bright_cyan,
        toolbar: color.dark_background,
        toolbar_text: toolbarText,
        toolbar_field: color.darker_background,
        toolbar_field_text: toolbarFieldText,
        toolbar_field_focus: color.background,
        toolbar_field_text_focus: toolbarFieldFocusText,
        toolbar_field_border: color.muted,
        toolbar_field_border_focus: color.bright_blue,
        toolbar_field_highlight: color.selection,
        toolbar_field_highlight_text: highlightText,
        button_background_hover: buttonBackgroundHover,
        button_background_active: buttonBackgroundActive,
        icons: color.light_foreground,
        icons_attention: color.bright_yellow,
        bookmark_text: toolbarText,
        popup: color.dark_background,
        popup_text: toolbarText,
        popup_border: color.muted,
        popup_highlight: selectedRowBackground,
        popup_highlight_text: selectedRowText,
        sidebar: color.dark_background,
        sidebar_text: toolbarText,
        sidebar_border: color.muted,
        sidebar_highlight: selectedRowBackground,
        sidebar_highlight_text: selectedRowText,
        ntp_background: color.background,
        ntp_card_background: color.lighter_background,
        ntp_text: tabBackgroundText,
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
