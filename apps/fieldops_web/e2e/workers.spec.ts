import { test, expect } from '@playwright/test';

test.describe('Workers', () => {
  test('worker search stays private before sign-in', async ({ page }) => {
    await page.goto('/workers');
    await expect(page.locator('#email')).toBeVisible({ timeout: 10000 });
    await expect(page.locator('input[placeholder*="earch"], input[placeholder*="uscar"]')).toHaveCount(0);
  });

  test('worker export controls stay private before sign-in', async ({ page }) => {
    await page.goto('/workers');
    const exportBtn = page.locator('button:has-text("CSV"), button:has-text("Export")');
    await expect(page.locator('#email')).toBeVisible({ timeout: 10000 });
    await expect(exportBtn).toHaveCount(0);
  });
});
