import { defineConfig } from "@playwright/test";

export default defineConfig({
  testDir: "./e2e",
  timeout: 45_000,
  fullyParallel: false,
  workers: 1,
  reporter: "line",
  use: {
    baseURL: "http://127.0.0.1:4173",
    browserName: "chromium",
    channel: "chrome",
    headless: true,
    viewport: { width: 1440, height: 1000 }
  },
  webServer: {
    command: "npm run preview:test",
    url: "http://127.0.0.1:4173/alunos/",
    reuseExistingServer: false,
    timeout: 30_000
  }
});
