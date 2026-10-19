import { test, expect } from '@playwright/test';

test.describe('Settings', () => {
  test('settings page should have tabs', async ({ page }) => {
    await page.goto('/settings');
    // Should show tab navigation
    await expect(page.locator('text=General')).toBeVisible({ timeout: 10000 });
  });
});
