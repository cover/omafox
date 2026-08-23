"use strict";

(function startOmafox() {
  const STORAGE_KEY = "storedTheme";
  const ERROR_KEY = "lastError";
  const NATIVE_STATUS_KEY = "nativeStatus";
  const NATIVE_HOST = "org.omarchy.omafox";
  const { parseThemeMessage, toFirefoxTheme } = globalThis.OmafoxTheme;
  let updateQueue = Promise.resolve();
  let nativePort = null;
  let reconnectTimer = null;
  let reconnectDelay = 1000;

  function errorRecord(error) {
    return {
      message: error instanceof Error ? error.message : String(error),
      occurredAt: new Date().toISOString()
    };
  }

  async function applyRecord(record) {
    await browser.theme.update(toFirefoxTheme(record));
  }

  async function restoreStoredTheme() {
    try {
      const result = await browser.storage.local.get(STORAGE_KEY);
      if (result[STORAGE_KEY]) {
        await applyRecord(result[STORAGE_KEY]);
      }
    } catch (error) {
      await browser.storage.local.set({ [ERROR_KEY]: errorRecord(error) });
      console.error("Omafox could not restore its stored theme", error);
    }
  }

  async function receiveThemeMessage(message) {
    try {
      const record = parseThemeMessage(message);
      await applyRecord(record);
      await browser.storage.local.set({ [STORAGE_KEY]: record });
      await browser.storage.local.remove(ERROR_KEY);
    } catch (error) {
      await browser.storage.local.set({ [ERROR_KEY]: errorRecord(error) });
      console.error("Omafox rejected a theme update", error);
    }
  }

  function enqueue(operation, label) {
    updateQueue = updateQueue
      .then(operation)
      .catch((error) => console.error(`Omafox ${label} queue failed`, error));
    return updateQueue;
  }

  function queueRestore() {
    return enqueue(restoreStoredTheme, "restore");
  }

  async function setNativeStatus(connected, message = "") {
    await browser.storage.local.set({
      [NATIVE_STATUS_KEY]: {
        connected,
        message,
        checkedAt: new Date().toISOString()
      }
    });
  }

  function scheduleNativeReconnect() {
    if (reconnectTimer !== null) return;
    reconnectTimer = setTimeout(() => {
      reconnectTimer = null;
      connectNativeHost();
    }, reconnectDelay);
    reconnectDelay = Math.min(reconnectDelay * 2, 30000);
  }

  function connectNativeHost() {
    if (nativePort) return;

    try {
      const port = browser.runtime.connectNative(NATIVE_HOST);
      nativePort = port;

      port.onMessage.addListener((message) => {
        reconnectDelay = 1000;
        void setNativeStatus(true);
        void enqueue(() => receiveThemeMessage(message), "native update");
      });

      port.onDisconnect.addListener(() => {
        if (nativePort === port) nativePort = null;
        const message = port.error?.message || "Native host disconnected";
        void setNativeStatus(false, message);
        scheduleNativeReconnect();
      });

      void setNativeStatus(true);
    } catch (error) {
      nativePort = null;
      void setNativeStatus(false, error instanceof Error ? error.message : String(error));
      scheduleNativeReconnect();
    }
  }

  function handleBrowserLifecycle() {
    const restore = queueRestore();
    connectNativeHost();
    return restore;
  }

  browser.runtime.onStartup.addListener(handleBrowserLifecycle);
  browser.runtime.onInstalled.addListener(handleBrowserLifecycle);
  void handleBrowserLifecycle();
})();
