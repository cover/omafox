"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { execFileSync, spawn } = require("node:child_process");

const projectDir = path.resolve(__dirname, "..");
const testDir = fs.mkdtempSync(path.join(os.tmpdir(), "omafox-native-host-"));
const sourcePath = path.join(projectDir, "omarchy", "omafox-native-host.c");
const hostPath = path.join(testDir, "omafox-native-host");
const stateFile = path.join(testDir, "theme.json");
const firstMessage = {
  protocol: "omafox",
  version: 1,
  action: "theme-set",
  theme: "first",
  palette: {}
};
const secondMessage = { ...firstMessage, theme: "second" };
const firstPayload = JSON.stringify(firstMessage);
const secondPayload = JSON.stringify(secondMessage);

function waitFor(predicate, message) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(message)), 2000);
    const check = () => {
      if (predicate()) {
        clearTimeout(timer);
        resolve();
      } else {
        setTimeout(check, 10);
      }
    };
    check();
  });
}

(async () => {
  execFileSync("cc", [
    "-std=c17",
    "-Os",
    "-fstack-protector-strong",
    "-fPIE",
    "-Wall",
    "-Wextra",
    "-Wpedantic",
    "-Werror",
    "-o",
    hostPath,
    sourcePath,
    "-pie",
    "-Wl,-z,relro,-z,now",
    "-Wl,--as-needed",
    "-s"
  ]);
  fs.writeFileSync(stateFile, `${firstPayload}\n`, { mode: 0o600 });

  const child = spawn(hostPath, [], {
    env: { ...process.env, OMAFOX_STATE_FILE: stateFile },
    stdio: ["pipe", "pipe", "pipe"]
  });
  const messages = [];
  let output = Buffer.alloc(0);
  let errors = "";

  child.stderr.setEncoding("utf8");
  child.stderr.on("data", (chunk) => {
    errors += chunk;
  });
  child.stdout.on("data", (chunk) => {
    output = Buffer.concat([output, chunk]);
    while (output.length >= 4) {
      const length = os.endianness() === "LE"
        ? output.readUInt32LE(0)
        : output.readUInt32BE(0);
      if (output.length < 4 + length) return;
      messages.push(JSON.parse(output.subarray(4, 4 + length).toString("utf8")));
      output = output.subarray(4 + length);
    }
  });

  try {
    await waitFor(() => messages.length >= 1, "native host did not send initial state");
    assert.deepEqual(messages[0], firstMessage);

    const nextStateFile = path.join(testDir, ".theme.json.next");
    fs.writeFileSync(nextStateFile, `${secondPayload}\n`, { mode: 0o600 });
    fs.renameSync(nextStateFile, stateFile);
    await waitFor(() => messages.length >= 2, "native host did not send changed state");
    assert.deepEqual(messages[1], secondMessage);

    fs.unlinkSync(stateFile);
    const restoredStateFile = path.join(testDir, ".theme.json.restored");
    fs.writeFileSync(restoredStateFile, `${secondPayload}\n`, { mode: 0o600 });
    fs.renameSync(restoredStateFile, stateFile);
    await waitFor(
      () => messages.length >= 3,
      "native host did not resend state after recreation"
    );
    assert.deepEqual(messages[2], secondMessage);

    child.stdin.end();
    const [exitCode] = await new Promise((resolve, reject) => {
      child.once("error", reject);
      child.once("exit", (...args) => resolve(args));
    });
    assert.equal(exitCode, 0, errors);
    assert.equal(output.length, 0, "native host emitted an incomplete frame");
  } finally {
    if (child.exitCode === null) child.kill();
    fs.rmSync(testDir, { recursive: true, force: true });
  }

  console.log("native-host.test.js: ok");
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
