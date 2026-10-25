import { test, expect } from '@playwright/test';

test.describe('Platform console invitation entry', () => {
  test('rejects an invalid invitation without exposing a password form', async ({ page }) => {
    await page.goto('/accept-company-invite?invitation=not-a-uuid', { waitUntil: 'domcontentloaded' });
    await expect(page.getByRole('heading', { name: 'Activar acceso corporativo' })).toBeVisible();
    await expect(page.locator('main [role="alert"]')).toContainText(/no es válido|venció/i);
    await expect(page.getByLabel('Nueva contraseña')).toHaveCount(0);
  });

  test('keeps the invalid-invitation recovery flow usable at a phone viewport', async ({ page }) => {
    await page.setViewportSize({ width: 375, height: 812 });
    await page.goto('/accept-company-invite?invitation=invalid', { waitUntil: 'domcontentloaded' });
    await expect(page.getByRole('heading', { name: 'Activar acceso corporativo' })).toBeVisible();
    const documentWidth = await page.evaluate(() => document.documentElement.scrollWidth);
    expect(documentWidth).toBeLessThanOrEqual(376);
  });
});

test('authenticated platform administrator can navigate the console on desktop and mobile', async ({ page }) => {
  const email = process.env.E2E_SUPERADMIN_EMAIL;
  const password = process.env.E2E_SUPERADMIN_PASSWORD;
  test.skip(!email || !password, 'Requires an authorized read-only platform-superadmin test account in environment variables.');

  const pageErrors: string[] = [];
  page.on('pageerror', (error) => pageErrors.push(error.message));
  await page.goto('/', { waitUntil: 'domcontentloaded' });
  await page.locator('#email').fill(email!);
  await page.locator('#password').fill(password!);
  await page.locator('form').getByRole('button', { name: /sign in|iniciar sesión/i }).click();
  await expect(page).toHaveURL(/\/platform(?:$|\?)/, { timeout: 20000 });
  await expect(page.getByRole('heading', { name: 'Administración de plataforma' })).toBeVisible();

  await page.setViewportSize({ width: 390, height: 844 });
  for (const tab of ['Clientes', 'Sucursales', 'Licencias', 'Invitaciones', 'Auditoría']) {
    await page.getByRole('tab', { name: tab }).click();
    await expect(page.getByRole('tab', { name: tab })).toHaveAttribute('aria-selected', 'true');
  }
  await page.setViewportSize({ width: 1440, height: 900 });
  await page.getByRole('tab', { name: 'Resumen' }).click();
  expect(pageErrors).toEqual([]);
});
