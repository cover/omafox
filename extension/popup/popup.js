"use strict";

(function startPopup() {
  const STORAGE_KEY = "storedTheme";
  const ERROR_KEY = "lastError";
  const NATIVE_STATUS_KEY = "nativeStatus";
  const state = document.querySelector("#state");
  const details = document.querySelector("#details");
  const themeName = document.querySelector("#theme-name");
  const paletteMode = document.querySelector("#palette-mode");
  const lastSync = document.querySelector("#last-sync");
  const errorMessage = document.querySelector("#error");
  const reapply = document.querySelector("#reapply");
  const clear = document.querySelector("#clear");
  let storedTheme = null;

  function showError(message) {
    errorMessage.textContent = message;
    errorMessage.hidden = !message;
  }

  async function loadState() {
    const result = await browser.storage.local.get([
      STORAGE_KEY,
      ERROR_KEY,
      NATIVE_STATUS_KEY
    ]);
    storedTheme = result[STORAGE_KEY] || null;
    const nativeStatus = result[NATIVE_STATUS_KEY] || null;

    if (storedTheme) {
      state.textContent = nativeStatus?.connected === false
        ? "Theme loaded; native helper is disconnected"
        : "Theme sync is active";
      themeName.textContent = storedTheme.themeName;
      paletteMode.textContent = `${storedTheme.palette.mode}, ${globalThis.OmafoxTheme.COLOR_KEYS.length} colors`;
      lastSync.textContent = new Date(storedTheme.appliedAt).toLocaleString();
      details.hidden = false;
      reapply.disabled = false;
      clear.disabled = false;
    } else {
      state.textContent = nativeStatus?.connected === false
        ? "Waiting for the native helper"
        : "Waiting for the first Omarchy sync";
      details.hidden = true;
      reapply.disabled = true;
      clear.disabled = true;
    }

    const nativeError = nativeStatus?.connected === false
      ? nativeStatus.message
      : "";
    showError(result[ERROR_KEY]?.message || nativeError || "");
  }

  reapply.addEventListener("click", async () => {
    if (!storedTheme) return;
    try {
      await browser.theme.update(globalThis.OmafoxTheme.toFirefoxTheme(storedTheme));
      await browser.storage.local.remove(ERROR_KEY);
      showError("");
      state.textContent = "Theme reapplied";
    } catch (error) {
      showError(error instanceof Error ? error.message : String(error));
    }
  });

  clear.addEventListener("click", async () => {
    try {
      await browser.theme.reset();
      await browser.storage.local.remove([STORAGE_KEY, ERROR_KEY]);
      await loadState();
    } catch (error) {
      showError(error instanceof Error ? error.message : String(error));
    }
  });

  void loadState().catch((error) => showError(error.message));
})();
