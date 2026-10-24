import { test, expect } from '@playwright/test';

test.describe('Settings', () => {
  test('settings remain behind the sign-in gate', async ({ page }) => {
    await page.goto('/settings');
    await expect(page.locator('#email')).toBeVisible({ timeout: 10000 });
    await expect(page.getByText('General', { exact: true })).toHaveCount(0);
  });
});
