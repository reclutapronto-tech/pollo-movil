import { defineConfig } from '@playwright/test';

const defaultPort = process.env.PLAYWRIGHT_PORT ?? '4318';
const baseURL = process.env.PLAYWRIGHT_BASE_URL ?? `http://127.0.0.1:${defaultPort}`;
const baseURLObject = new URL(baseURL);
const port = process.env.PLAYWRIGHT_PORT ?? (baseURLObject.port || '3000');

export default defineConfig({
  testDir: './e2e',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: 'html',
  use: {
    baseURL,
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
  },
  webServer: {
    // E2E runs against the production build created by the preceding build step.
    // A dedicated port and no reuse prevent collisions with local services (e.g. Grafana).
    command: `node node_modules/next/dist/bin/next start --hostname 127.0.0.1 --port ${port}`,
    url: baseURL,
    reuseExistingServer: false,
    timeout: 60000,
  },
});
