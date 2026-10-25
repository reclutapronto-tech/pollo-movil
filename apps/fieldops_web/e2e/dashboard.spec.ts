import { test, expect } from '@playwright/test';

test.describe('Dashboard', () => {
  test('does not expose private dashboard content before sign-in', async ({ page }) => {
    await page.goto('/');
    await expect(page.locator('#email')).toBeVisible();
    await expect(page.getByRole('navigation')).toHaveCount(0);
  });

  test('keeps the sign-in gate after protected-route navigation', async ({ page }) => {
    await page.goto('/restaurant');
    await expect(page.locator('#email')).toBeVisible();
    await expect(page.locator('#password')).toBeVisible();
  });
});
