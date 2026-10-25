import { test, expect } from '@playwright/test';

test.describe('Authentication', () => {
  test('should show login page for unauthenticated users', async ({ page }) => {
    await page.goto('/', { waitUntil: 'domcontentloaded' });
    await expect(page.locator('#email')).toBeVisible();
    await expect(page.locator('#password')).toBeVisible();
  });

  test('expired Supabase recovery fragment shows a safe recovery message', async ({ page }) => {
    await page.goto('/reset-password#error=access_denied&error_code=otp_expired&error_description=Email+link+is+invalid+or+has+expired', { waitUntil: 'domcontentloaded' });
    await expect(page.getByRole('heading', { name: 'Crear una contraseña nueva' })).toBeVisible();
    await expect(page.locator('main [role="alert"]')).toContainText('ya venció o fue utilizado');
    await expect(page.getByRole('link', { name: 'Volver al inicio de sesión' })).toHaveAttribute('href', '/');
    await expect(page.getByLabel('Contraseña nueva')).toHaveCount(0);
  });

  test('invalid PKCE code does not crash the recovery page', async ({ page }) => {
    await page.goto('/reset-password?code=invalid-ci-recovery-code', { waitUntil: 'domcontentloaded' });
    await expect(page.getByRole('heading', { name: 'Crear una contraseña nueva' })).toBeVisible();
    await expect(page.locator('main [role="alert"]')).toBeVisible();
    await expect(page.getByRole('link', { name: 'Volver al inicio de sesión' })).toBeVisible();
    await expect(page.getByLabel('Contraseña nueva')).toHaveCount(0);
  });

  test('expired implicit-flow session is rejected before showing the password form', async ({ page }) => {
    await page.goto('/reset-password#access_token=eyJhbGciOiJIUzI1NiJ9.eyJleHAiOjF9.c2ln&refresh_token=expired-ci-refresh-token&expires_in=0&expires_at=1&token_type=bearer&type=recovery', { waitUntil: 'domcontentloaded' });
    await expect(page.getByRole('heading', { name: 'Crear una contraseña nueva' })).toBeVisible();
    await expect(page.locator('main [role="alert"]')).toContainText(/venció|válida/);
    await expect(page.getByLabel('Contraseña nueva')).toHaveCount(0);
  });

  test('unauthenticated users are sent to login instead of the platform panel', async ({ page }) => {
    await page.goto('/platform', { waitUntil: 'domcontentloaded' });
    await expect(page.locator('#email')).toBeVisible();
    await expect(page.getByRole('heading', { name: /platform/i })).toHaveCount(0);
  });

  test('should show sign out button when authenticated', async () => {
    // This test would need auth fixtures — skip with annotation for now
    test.skip(true, 'Requires auth fixtures');
  });
});
