import { readFileSync } from "node:fs";
import { type Server, createServer } from "node:https";
import { join } from "node:path";
import { parse } from "node:url";
import { BrowserWindow, app, dialog, shell } from "electron";
import next from "next";
import { isProviderAuthorizationUrl } from "./navigation";

const HOST = "127.0.0.1";
const PORT = process.env.BLATHER_E2E === "1" ? Number(process.env.BLATHER_PORT ?? 3199) : 3000;
const APP_ORIGIN = `https://${HOST}:${PORT}`;

let mainWindow: BrowserWindow | null = null;
let server: Server | null = null;
let nextApp: ReturnType<typeof next> | null = null;

// The window is restricted to Blather's loopback server, while provider pages
// open in the system browser. This avoids requiring Electron to trust mkcert.
app.commandLine.appendSwitch("ignore-certificate-errors");

function projectDir(): string {
  return app.isPackaged ? app.getAppPath() : process.cwd();
}

if (!app.isPackaged && process.env.BLATHER_E2E === "1") {
  app.setPath("userData", join(projectDir(), ".tmp", "e2e-electron-user-data"));
}

function certificateDir(): string {
  return app.isPackaged
    ? join(process.resourcesPath, "certificates")
    : join(projectDir(), "certificates");
}

function setMacAppIcon(): void {
  if (process.platform !== "darwin") return;
  app.dock?.setIcon(join(projectDir(), "assets", "blather-desktop-icon.png"));
}

async function startServer(): Promise<void> {
  process.env.BLATHER_PORT = String(PORT);
  process.env.NEXT_TELEMETRY_DISABLED = "1";
  if (!app.isPackaged && process.env.BLATHER_E2E === "1") {
    process.env.BLATHER_NEXT_E2E_DEV = "1";
  }

  nextApp = next({
    dev: !app.isPackaged,
    dir: projectDir(),
    hostname: HOST,
    port: PORT,
  });
  console.info(`Starting Blather server at ${APP_ORIGIN}`);
  await nextApp.prepare();
  console.info("Blather server is ready");

  const certDir = certificateDir();
  const handle = nextApp.getRequestHandler();
  server = createServer(
    {
      cert: readFileSync(join(certDir, "localhost.pem")),
      key: readFileSync(join(certDir, "localhost-key.pem")),
    },
    (request, response) => {
      void handle(request, response, parse(request.url ?? "", true));
    },
  );

  await new Promise<void>((resolve, reject) => {
    server?.once("error", reject);
    server?.listen(PORT, HOST, () => {
      server?.off("error", reject);
      resolve();
    });
  });
}

async function stopServer(): Promise<void> {
  const runningNextApp = nextApp;
  nextApp = null;

  if (server) {
    const runningServer = server;
    server = null;
    runningServer.close();
    runningServer.closeAllConnections();
  }

  await runningNextApp?.close();
}

async function cleanupOnStartupFailure(): Promise<void> {
  const runningServer = server;
  server = null;
  runningServer?.closeAllConnections();
  await nextApp?.close();
  nextApp = null;
}

function openProviderAuthorization(url: string): void {
  if (process.env.BLATHER_DISABLE_EXTERNAL_LINKS === "1") return;
  void shell.openExternal(url);
}

function createWindow(): void {
  mainWindow = new BrowserWindow({
    width: 1280,
    height: 900,
    minWidth: 900,
    minHeight: 700,
    show: false,
    icon: join(projectDir(), "assets", "blather-desktop-icon.png"),
    webPreferences: {
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
    },
  });

  mainWindow.once("ready-to-show", () => mainWindow?.show());
  mainWindow.on("closed", () => {
    mainWindow = null;
  });

  mainWindow.webContents.setWindowOpenHandler(({ url }) => {
    if (isProviderAuthorizationUrl(url)) openProviderAuthorization(url);
    return { action: "deny" };
  });
  mainWindow.webContents.on("will-navigate", (event, url) => {
    if (url.startsWith(`${APP_ORIGIN}/`) || url === APP_ORIGIN) return;
    event.preventDefault();
    if (isProviderAuthorizationUrl(url)) openProviderAuthorization(url);
  });

  void mainWindow.loadURL(APP_ORIGIN);
}

async function bootstrap(): Promise<void> {
  try {
    await startServer();
    createWindow();
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown startup error";
    console.error("Blather startup failed:", error);
    await cleanupOnStartupFailure();
    dialog.showErrorBox("Blather could not start", message);
    app.quit();
  }
}

function launch(): void {
  void app.whenReady().then(() => {
    setMacAppIcon();
    return bootstrap();
  });
}

app.on("second-instance", () => {
  if (!mainWindow) {
    createWindow();
    return;
  }
  if (mainWindow.isMinimized()) mainWindow.restore();
  mainWindow.focus();
});

app.on("window-all-closed", () => app.quit());
app.on("before-quit", (event) => {
  if (!server) return;
  event.preventDefault();
  void stopServer().finally(() => app.exit());
});

if (process.env.BLATHER_E2E === "1") {
  launch();
} else if (!app.requestSingleInstanceLock()) {
  app.quit();
} else {
  launch();
}
