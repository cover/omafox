"use strict";

const assert = require("node:assert/strict");
const manifest = require("../extension/manifest.json");
const nativeManifest = require("../packaging/org.omarchy.omafox.json");
const themeApi = require("../extension/theme.js");

const memory = {};
const themeUpdates = [];
let startupListener;
let nativeHostName;
let nativeMessageListener;
let nativeDisconnectListener;

const nativePort = {
  error: null,
  onMessage: {
    addListener(listener) {
      nativeMessageListener = listener;
    }
  },
  onDisconnect: {
    addListener(listener) {
      nativeDisconnectListener = listener;
    }
  }
};

function keysFromRequest(keys) {
  if (typeof keys === "string") return [keys];
  if (Array.isArray(keys)) return keys;
  return Object.keys(keys || memory);
}

global.browser = {
  theme: {
    async update(theme) {
      themeUpdates.push(theme);
    }
  },
  storage: {
    local: {
      async get(keys) {
        return Object.fromEntries(
          keysFromRequest(keys)
            .filter((key) => Object.hasOwn(memory, key))
            .map((key) => [key, memory[key]])
        );
      },
      async set(values) {
        Object.assign(memory, values);
      },
      async remove(keys) {
        for (const key of keysFromRequest(keys)) delete memory[key];
      }
    }
  },
  runtime: {
    connectNative(name) {
      nativeHostName = name;
      return nativePort;
    },
    onStartup: {
      addListener(listener) {
        startupListener = listener;
      }
    },
    onInstalled: {
      addListener() {}
    }
  }
};

require("../extension/background.js");

function waitFor(predicate, message) {
  return new Promise((resolve, reject) => {
    const deadline = Date.now() + 1000;
    const check = () => {
      if (predicate()) return resolve();
      if (Date.now() >= deadline) return reject(new Error(message));
      setTimeout(check, 5);
    };
    check();
  });
}

(async () => {
  assert.deepEqual(manifest.permissions, ["nativeMessaging", "storage", "theme"]);
  assert.equal(Object.hasOwn(manifest, "host_permissions"), false);
  assert.equal(nativeHostName, nativeManifest.name);
  assert.deepEqual(nativeManifest.allowed_extensions, [
    manifest.browser_specific_settings.gecko.id
  ]);
  assert.equal(typeof nativeMessageListener, "function");
  assert.equal(typeof nativeDisconnectListener, "function");

  const palette = Object.fromEntries(
    themeApi.PALETTE_KEYS.map((key) => [key, key === "mode" ? "light" : "#123456"])
  );
  const message = {
    protocol: themeApi.PROTOCOL,
    version: themeApi.SCHEMA_VERSION,
    action: themeApi.ACTION,
    theme: "test-light",
    palette
  };

  nativeMessageListener(message);
  await waitFor(
    () => memory.storedTheme?.themeName === "test-light",
    "native theme update was not applied"
  );
  assert.equal(memory.storedTheme.palette.mode, "light");
  assert.equal(themeUpdates.at(-1).properties.color_scheme, "light");
  assert.equal(memory.lastError, undefined);

  const nativePalette = Object.fromEntries(
    themeApi.PALETTE_KEYS.map((key) => [key, key === "mode" ? "dark" : "#654321"])
  );
  const nativeMessage = {
    protocol: themeApi.PROTOCOL,
    version: themeApi.SCHEMA_VERSION,
    action: themeApi.ACTION,
    theme: "native-dark",
    palette: nativePalette
  };
  nativeMessageListener(nativeMessage);
  await waitFor(
    () => memory.storedTheme?.themeName === "native-dark",
    "native theme update was not applied"
  );
  assert.equal(themeUpdates.at(-1).properties.color_scheme, "dark");
  assert.equal(memory.nativeStatus.connected, true);

  const updatesBeforeRestart = themeUpdates.length;
  await startupListener();
  assert.equal(themeUpdates.length, updatesBeforeRestart + 1);
  assert.equal(themeUpdates.at(-1).colors.frame, "#654321");

  const originalConsoleError = console.error;
  console.error = () => {};
  nativeMessageListener({
    protocol: themeApi.PROTOCOL,
    version: themeApi.SCHEMA_VERSION,
    action: themeApi.ACTION,
    theme: "broken",
    palette: {}
  });
  await waitFor(() => memory.lastError, "invalid native update was not rejected");
  console.error = originalConsoleError;
  assert.match(memory.lastError.message, /mode/);
  assert.equal(memory.storedTheme.themeName, "native-dark");

  console.log("background.test.js: ok");
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
