import { test, expect } from '@playwright/test';

test.describe('Workers', () => {
  test('should show search input', async ({ page }) => {
    await page.goto('/workers');
    const search = page.locator('input[placeholder*="earch"]');
    await expect(search).toBeVisible({ timeout: 10000 });
  });

  test('should have CSV export button', async ({ page }) => {
    await page.goto('/workers');
    const exportBtn = page.locator('button:has-text("CSV"), button:has-text("Export")');
    await expect(exportBtn).toBeVisible({ timeout: 10000 });
  });
});
