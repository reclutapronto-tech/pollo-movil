import { test, expect } from '@playwright/test';

test.describe('Navigation', () => {
  test('does not render protected navigation before sign-in', async ({ page }) => {
    await page.goto('/');
    await expect(page.locator('#email')).toBeVisible();
    await expect(page.locator('a[href="/workers"], a[href="/schedule"], a[href="/reports"]')).toHaveCount(0);
  });

  test('sidebar should collapse and expand', async ({ page }) => {
    test.skip(true, 'Requires authenticated browser fixtures.');
    await page.goto('/');
  });

  test('keeps restaurant operations routes behind authentication', async ({ page }) => {
    for (const route of ['/restaurant/configuration', '/restaurant/calendar', '/restaurant/coverage']) {
      await page.goto(route);
      await expect(page.locator('#email')).toBeVisible();
      await expect(page.getByRole('navigation')).toHaveCount(0);
    }
  });
});
