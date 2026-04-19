#!/usr/bin/env node

import { spawn } from "node:child_process";
import { mkdtemp, rm } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { pathToFileURL } from "node:url";

const DEFAULTS = {
  sshHost: process.env.BRUH_SELFHOST_SSH_HOST || "210.73.43.5",
  sshPort: process.env.BRUH_SELFHOST_SSH_PORT || "17322",
  sshUser: process.env.BRUH_SELFHOST_SSH_USER || "root",
  authDir: process.env.BRUH_XHS_AUTH_DIR ||
    path.resolve("tools/xhs/.auth"),
  sharedModule: process.env.BRUH_XHS_SHARED_MODULE ||
    path.resolve("tools/xhs/_shared.mjs"),
  remoteStateFile: process.env.BRUH_XHS_REMOTE_STATE_FILE ||
    "/opt/bruh-selfhost/runtime/xhs-storage-state.json",
};

function spawnAndCollect(command, args, options = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      stdio: ["ignore", "pipe", "pipe"],
      ...options,
    });
    let stdout = "";
    let stderr = "";
    child.stdout?.on("data", (chunk) => {
      stdout += chunk.toString();
    });
    child.stderr?.on("data", (chunk) => {
      stderr += chunk.toString();
    });
    child.on("error", reject);
    child.on("close", (code) => {
      if (code === 0) {
        resolve({ stdout, stderr });
        return;
      }
      reject(new Error(stderr || stdout || `${command} exited with code ${code}`));
    });
  });
}

async function promptSecret(question) {
  process.stdout.write(question);
  const stdin = process.stdin;
  stdin.setRawMode?.(true);
  stdin.resume();
  stdin.setEncoding("utf8");

  return await new Promise((resolve) => {
    let value = "";
    const onData = (chunk) => {
      const text = String(chunk);
      for (const char of text) {
        if (char === "\r" || char === "\n") {
          stdin.off("data", onData);
          stdin.setRawMode?.(false);
          stdin.pause();
          process.stdout.write("\n");
          resolve(value);
          return;
        }
        if (char === "\u0003") {
          stdin.off("data", onData);
          stdin.setRawMode?.(false);
          stdin.pause();
          process.stdout.write("\n");
          process.exit(1);
        }
        if (char === "\u007f") {
          value = value.slice(0, -1);
          continue;
        }
        value += char;
      }
    };
    stdin.on("data", onData);
  });
}

async function confirmAuthDir() {
  const { stdout } = await spawnAndCollect("bash", ["-lc", `
    if [[ -d "${DEFAULTS.authDir}" ]]; then
      ls -la "${DEFAULTS.authDir}"
    else
      echo "MISSING_AUTH_DIR"
      exit 2
    fi
  `]);
  return stdout;
}

async function exportStorageState(outputPath) {
  const { createContext } = await import(pathToFileURL(DEFAULTS.sharedModule).href);
  const context = await createContext({ headless: true });
  try {
    await context.storageState({ path: outputPath });
  } finally {
    await context.close();
  }
}

async function uploadStorageState(sshPassword) {
  const tmpDir = await mkdtemp(path.join(os.tmpdir(), "bruh-xhs-auth-"));
  const statePath = path.join(tmpDir, "xhs-storage-state.json");

  try {
    await exportStorageState(statePath);

    const expectScp = `
      set timeout 180
      spawn scp -P $env(SSH_PORT) $env(STATE_PATH) $env(SSH_USER)@$env(SSH_HOST):$env(REMOTE_STATE_FILE)
      expect {
        -re ".*assword:" { send "$env(SSH_PASSWORD)\\r"; exp_continue }
        eof
      }
    `;
    await spawnAndCollect("expect", ["-c", expectScp], {
      env: {
        ...process.env,
        SSH_HOST: DEFAULTS.sshHost,
        SSH_PORT: DEFAULTS.sshPort,
        SSH_USER: DEFAULTS.sshUser,
        SSH_PASSWORD: sshPassword,
        STATE_PATH: statePath,
        REMOTE_STATE_FILE: DEFAULTS.remoteStateFile,
      },
    });
  } finally {
    await rm(tmpDir, { recursive: true, force: true }).catch(() => null);
  }
}

async function main() {
  console.log("准备将本地小红书登录态同步到服务器。");
  console.log(`本地 auth 目录: ${DEFAULTS.authDir}`);
  console.log(
    `目标服务器: ${DEFAULTS.sshUser}@${DEFAULTS.sshHost}:${DEFAULTS.sshPort}`,
  );
  console.log(`目标状态文件: ${DEFAULTS.remoteStateFile}`);

  const listing = await confirmAuthDir();
  if (listing.trim()) {
    console.log(listing.trim());
  }

  const sshPassword = process.env.BRUH_SELFHOST_SSH_PASSWORD ||
    await promptSecret("请输入服务器 SSH 密码: ");
  if (!sshPassword) {
    throw new Error("缺少 SSH 密码。");
  }

  await uploadStorageState(sshPassword);
  console.log("XHS storage state 已同步到服务器。");
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
});
