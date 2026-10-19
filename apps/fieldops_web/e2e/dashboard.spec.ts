import { test, expect } from '@playwright/test';

test.describe('Dashboard', () => {
  test('should display KPI cards', async ({ page }) => {
    await page.goto('/');
    // KPI cards should show
    const kpiCards = page.locator('[class*="rounded-2xl"][class*="border"]');
    await expect(kpiCards.first()).toBeVisible({ timeout: 10000 });
  });

  test('should show loading skeletons initially', async ({ page }) => {
    await page.goto('/');
    // Skeletons should appear briefly
    await expect(page.locator('[class*="animate-pulse"]').first()).toBeAttached();
    // May or may not catch it depending on load speed
  });
});
