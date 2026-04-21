#!/usr/bin/env node

import { spawn } from "node:child_process";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { createRequire } from "node:module";
import os from "node:os";
import path from "node:path";
import readline from "node:readline/promises";
import { setTimeout as sleep } from "node:timers/promises";
import { pathToFileURL } from "node:url";

const require = createRequire(import.meta.url);
const PLAYWRIGHT_MODULE = process.env.BRUH_PLAYWRIGHT_MODULE ||
  resolveOptionalModule("playwright");
const DEFAULT_EDGE_EXECUTABLE =
  "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge";

const DEFAULTS = {
  sshHost: process.env.BRUH_SELFHOST_SSH_HOST || "210.73.43.5",
  sshPort: process.env.BRUH_SELFHOST_SSH_PORT || "17322",
  sshUser: process.env.BRUH_SELFHOST_SSH_USER || "root",
  remoteEnvPath: process.env.BRUH_X_REMOTE_ENV_PATH ||
    "/opt/bruh-selfhost/runtime/.env",
  remoteServiceName: process.env.BRUH_X_REMOTE_SERVICE_NAME ||
    "bruh-x-scrape-service.service",
  remoteHealthUrl: process.env.BRUH_X_REMOTE_HEALTH_URL ||
    "http://127.0.0.1:8789/health",
  loginMode: process.env.BRUH_X_LOGIN_MODE || "edge_cdp",
  browserChannel: process.env.BRUH_X_LOGIN_BROWSER || "",
  browserExecutablePath: process.env.BRUH_X_LOGIN_EXECUTABLE_PATH || "",
  cdpPort: Number.parseInt(process.env.BRUH_X_LOGIN_CDP_PORT || "9222", 10),
};

function resolveOptionalModule(moduleName) {
  try {
    return require.resolve(moduleName);
  } catch {
    return "";
  }
}

function ensurePlaywrightAvailable() {
  if (!PLAYWRIGHT_MODULE) {
    throw new Error(
      "Playwright not found. Use the default BRUH_X_LOGIN_MODE=edge_cdp, run `npm install playwright`, or set BRUH_PLAYWRIGHT_MODULE to playwright/index.mjs.",
    );
  }

  return import(pathToFileURL(PLAYWRIGHT_MODULE).href).catch(() => {
    throw new Error(
      `Playwright not found at ${PLAYWRIGHT_MODULE}. Run 'npm install playwright' or set BRUH_PLAYWRIGHT_MODULE.`,
    );
  });
}

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

async function prompt(question) {
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });
  try {
    return (await rl.question(question)).trim();
  } finally {
    rl.close();
  }
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

function cookieValue(cookies, name) {
  return cookies.find((cookie) => cookie.name === name)?.value?.trim() || null;
}

async function captureCookiesWithPlaywrightBrowser() {
  const { chromium } = await ensurePlaywrightAvailable();
  const userDataDir = await mkdtemp(path.join(os.tmpdir(), "bruh-x-login-"));
  const launchOptions = {
    headless: false,
  };
  if (DEFAULTS.browserExecutablePath) {
    launchOptions.executablePath = DEFAULTS.browserExecutablePath;
  } else if (DEFAULTS.browserChannel) {
    launchOptions.channel = DEFAULTS.browserChannel;
  }

  const context = await chromium.launchPersistentContext(
    userDataDir,
    launchOptions,
  );

  try {
    const page = context.pages()[0] || await context.newPage();
    await page.goto("https://x.com/i/flow/login", {
      waitUntil: "domcontentloaded",
      timeout: 60000,
    });

    console.log("本地浏览器已打开。请在浏览器里完成 X 登录。");
    console.log("登录完成并确认主页已可访问后，回到终端按回车。");

    while (true) {
      const answer = await prompt("登录完成后按回车继续检测，输入 q 退出: ");
      if (answer.toLowerCase() === "q") {
        throw new Error("登录已取消，未采集到 auth_token/ct0。");
      }

      const cookies = await context.cookies(["https://x.com", "https://twitter.com"]);
      const authToken = cookieValue(cookies, "auth_token");
      const ct0 = cookieValue(cookies, "ct0");

      if (authToken && ct0) {
        return { authToken, ct0 };
      }

      console.log("还没有拿到 auth_token/ct0，请确认浏览器里已登录完成后再重试。");
    }
  } finally {
    await context.close().catch(() => null);
    await rm(userDataDir, { recursive: true, force: true }).catch(() => null);
  }
}

function launchEdgeWithRemoteDebugging(userDataDir) {
  const executablePath = DEFAULTS.browserExecutablePath || DEFAULT_EDGE_EXECUTABLE;
  const args = [
    `--remote-debugging-port=${DEFAULTS.cdpPort}`,
    `--user-data-dir=${userDataDir}`,
    "--no-first-run",
    "--no-default-browser-check",
    "https://x.com/i/flow/login",
  ];

  const child = spawn(executablePath, args, {
    detached: true,
    stdio: "ignore",
  });
  child.unref();

  return {
    executablePath,
    pid: child.pid,
  };
}

async function waitForDevToolsEndpoint() {
  const deadline = Date.now() + 30000;
  const endpoint = `http://127.0.0.1:${DEFAULTS.cdpPort}`;

  while (Date.now() < deadline) {
    try {
      const response = await fetch(`${endpoint}/json/version`);
      if (response.ok) {
        return endpoint;
      }
    } catch {
      // Wait for Edge to finish booting.
    }
    await sleep(500);
  }

  throw new Error(`Edge DevTools endpoint did not become ready on ${endpoint}.`);
}

async function waitForPageTarget(endpoint) {
  const deadline = Date.now() + 15000;

  while (Date.now() < deadline) {
    const response = await fetch(`${endpoint}/json/list`);
    if (!response.ok) {
      throw new Error(`Failed to list Edge DevTools targets: HTTP ${response.status}`);
    }

    const targets = await response.json();
    const pages = targets.filter((target) =>
      target.type === "page" && target.webSocketDebuggerUrl
    );
    const xPage = pages.find((target) =>
      /https?:\/\/(x|twitter)\.com\//i.test(target.url || "")
    );
    if (xPage) {
      return xPage;
    }
    if (pages[0]) {
      return pages[0];
    }

    await sleep(250);
  }

  throw new Error("Edge DevTools did not expose a page target.");
}

function openWebSocket(url) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(url);
    const cleanup = () => {
      ws.removeEventListener("open", onOpen);
      ws.removeEventListener("error", onError);
    };
    const onOpen = () => {
      cleanup();
      resolve(ws);
    };
    const onError = () => {
      cleanup();
      reject(new Error(`Failed to connect Edge DevTools websocket: ${url}`));
    };

    ws.addEventListener("open", onOpen);
    ws.addEventListener("error", onError);
  });
}

function createCdpClient(ws) {
  let nextId = 1;
  const pending = new Map();

  ws.addEventListener("message", (event) => {
    let message;
    try {
      message = JSON.parse(String(event.data));
    } catch {
      return;
    }

    const request = pending.get(message.id);
    if (!request) {
      return;
    }

    pending.delete(message.id);
    if (message.error) {
      request.reject(
        new Error(
          `${request.method} failed: ${message.error.message || JSON.stringify(message.error)}`,
        ),
      );
      return;
    }

    request.resolve(message.result || {});
  });

  ws.addEventListener("close", () => {
    for (const request of pending.values()) {
      request.reject(new Error("Edge DevTools websocket closed."));
    }
    pending.clear();
  });

  return {
    send(method, params = {}) {
      if (ws.readyState !== WebSocket.OPEN) {
        return Promise.reject(new Error("Edge DevTools websocket is not open."));
      }

      const id = nextId++;
      return new Promise((resolve, reject) => {
        pending.set(id, { method, resolve, reject });
        ws.send(JSON.stringify({ id, method, params }));
      });
    },
    close() {
      ws.close();
    },
  };
}

function stopDetachedProcess(pid) {
  if (!pid) {
    return;
  }
  try {
    process.kill(-pid, "SIGTERM");
  } catch {
    // Ignore cleanup errors from already-exited processes.
  }
}

async function captureCookiesWithEdgeCdp() {
  const userDataDir = await mkdtemp(path.join(os.tmpdir(), "bruh-x-edge-cdp-"));
  const launchedEdge = launchEdgeWithRemoteDebugging(userDataDir);
  let cdp;

  try {
    const endpoint = await waitForDevToolsEndpoint();
    const target = await waitForPageTarget(endpoint);
    const ws = await openWebSocket(target.webSocketDebuggerUrl);
    cdp = createCdpClient(ws);

    if (!/https?:\/\/(x|twitter)\.com\//i.test(target.url || "")) {
      await cdp.send("Page.navigate", { url: "https://x.com/i/flow/login" });
    }
    await cdp.send("Network.enable").catch(() => null);

    console.log("已启动真实 Microsoft Edge，并通过 CDP 附着。");
    console.log("请在浏览器里完成 X 登录。");
    console.log("登录完成并确认主页可访问后，回到终端按回车。");

    while (true) {
      const answer = await prompt("登录完成后按回车继续检测，输入 q 退出: ");
      if (answer.toLowerCase() === "q") {
        throw new Error("登录已取消，未采集到 auth_token/ct0。");
      }

      const { cookies = [] } = await cdp.send("Network.getCookies", {
        urls: ["https://x.com", "https://twitter.com"],
      });
      const authToken = cookieValue(cookies, "auth_token");
      const ct0 = cookieValue(cookies, "ct0");

      if (authToken && ct0) {
        return { authToken, ct0 };
      }

      console.log("还没有拿到 auth_token/ct0，请确认浏览器里已登录完成后再重试。");
    }
  } finally {
    cdp?.close();
    stopDetachedProcess(launchedEdge.pid);
    await rm(userDataDir, { recursive: true, force: true }).catch(() => null);
  }
}

function buildRemoteApplyScript() {
  return `#!/usr/bin/env bash
set -euo pipefail
python3 - <<'PY'
from pathlib import Path
source = Path('/tmp/bruh_x_cookies.env')
target = Path('${DEFAULTS.remoteEnvPath}')
updates = {}
for line in source.read_text().splitlines():
    line = line.strip()
    if not line or '=' not in line:
        continue
    key, value = line.split('=', 1)
    updates[key] = value

text = target.read_text() if target.exists() else ''
lines = text.splitlines()
for key, value in updates.items():
    marker = f"{key}="
    replaced = False
    for index, line in enumerate(lines):
        if line.startswith(marker):
            lines[index] = f"{key}={value}"
            replaced = True
            break
    if not replaced:
        lines.append(f"{key}={value}")

target.write_text('\\n'.join(lines) + '\\n')
source.unlink(missing_ok=True)
PY
systemctl restart ${DEFAULTS.remoteServiceName}
systemctl is-active ${DEFAULTS.remoteServiceName}
curl -s ${DEFAULTS.remoteHealthUrl}
`;
}

async function uploadCookiesToServer({
  authToken,
  ct0,
  sshPassword,
}) {
  const tmpDir = await mkdtemp(path.join(os.tmpdir(), "bruh-x-cookie-upload-"));
  const localCookieFile = path.join(tmpDir, "bruh_x_cookies.env");
  const localApplyFile = path.join(tmpDir, "bruh_apply_x_cookies.sh");

  try {
    await writeFile(
      localCookieFile,
      `TWITTER_AUTH_TOKEN=${authToken}\nTWITTER_CT0=${ct0}\n`,
      { mode: 0o600 },
    );
    await writeFile(localApplyFile, buildRemoteApplyScript(), { mode: 0o700 });

    const expectScp = `
      set timeout 120
      spawn scp -P $env(SSH_PORT) $env(LOCAL_COOKIE_FILE) $env(LOCAL_APPLY_FILE) $env(SSH_USER)@$env(SSH_HOST):/tmp/
      expect {
        -re ".*assword:" { send "$env(SSH_PASSWORD)\\r" }
      }
      expect eof
    `;
    await spawnAndCollect("expect", ["-c", expectScp], {
      env: {
        ...process.env,
        SSH_HOST: DEFAULTS.sshHost,
        SSH_PORT: DEFAULTS.sshPort,
        SSH_USER: DEFAULTS.sshUser,
        SSH_PASSWORD: sshPassword,
        LOCAL_COOKIE_FILE: localCookieFile,
        LOCAL_APPLY_FILE: localApplyFile,
      },
    });

    const expectSsh = `
      set timeout 120
      spawn ssh -o StrictHostKeyChecking=no -p $env(SSH_PORT) $env(SSH_USER)@$env(SSH_HOST) "bash /tmp/bruh_apply_x_cookies.sh"
      expect {
        -re ".*assword:" { send "$env(SSH_PASSWORD)\\r" }
      }
      expect eof
    `;
    const { stdout } = await spawnAndCollect("expect", ["-c", expectSsh], {
      env: {
        ...process.env,
        SSH_HOST: DEFAULTS.sshHost,
        SSH_PORT: DEFAULTS.sshPort,
        SSH_USER: DEFAULTS.sshUser,
        SSH_PASSWORD: sshPassword,
      },
    });

    return stdout;
  } finally {
    await rm(tmpDir, { recursive: true, force: true }).catch(() => null);
  }
}

async function main() {
  console.log("准备采集本地 X 登录 cookie，并直接写入服务器。");
  console.log(
    `目标服务器: ${DEFAULTS.sshUser}@${DEFAULTS.sshHost}:${DEFAULTS.sshPort}`,
  );
  if (DEFAULTS.loginMode === "edge_cdp") {
    console.log(`登录模式: edge_cdp @ 127.0.0.1:${DEFAULTS.cdpPort}`);
    console.log(
      `登录浏览器: ${DEFAULTS.browserExecutablePath || DEFAULT_EDGE_EXECUTABLE}`,
    );
  } else if (DEFAULTS.browserExecutablePath) {
    console.log(`登录浏览器: executablePath=${DEFAULTS.browserExecutablePath}`);
  } else if (DEFAULTS.browserChannel) {
    console.log(`登录浏览器: channel=${DEFAULTS.browserChannel}`);
  } else {
    console.log("登录浏览器: Playwright Chromium");
  }

  const sshPassword = process.env.BRUH_SELFHOST_SSH_PASSWORD ||
    await promptSecret("请输入服务器 SSH 密码: ");
  if (!sshPassword) {
    throw new Error("缺少 SSH 密码。");
  }

  const { authToken, ct0 } = DEFAULTS.loginMode === "edge_cdp"
    ? await captureCookiesWithEdgeCdp()
    : await captureCookiesWithPlaywrightBrowser();
  const uploadOutput = await uploadCookiesToServer({
    authToken,
    ct0,
    sshPassword,
  });

  console.log("Cookie 已上传到服务器并重启抓取服务。");
  const summary = uploadOutput
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => line.length > 0)
    .slice(-3)
    .join("\n");
  if (summary) {
    console.log(summary);
  }
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
});
