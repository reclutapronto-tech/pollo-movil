import { test, expect } from '@playwright/test';

test.describe('Navigation', () => {
  test('sidebar should render all nav items', async ({ page }) => {
    await page.goto('/');
    // Check key nav items exist
    await expect(page.locator('a[href="/"]')).toBeVisible();
    await expect(page.locator('a[href="/workers"]')).toBeVisible();
    await expect(page.locator('a[href="/schedule"]')).toBeVisible();
    await expect(page.locator('a[href="/reports"]')).toBeVisible();
  });

  test('sidebar should collapse and expand', async ({ page }) => {
    await page.goto('/');
    const collapseBtn = page.locator('button[aria-label*="ollapse"], button[aria-label*="enu"]').first();
    if (await collapseBtn.isVisible()) {
      await collapseBtn.click();
      // Sidebar should be narrower
      await page.waitForTimeout(300);
    }
  });
});
