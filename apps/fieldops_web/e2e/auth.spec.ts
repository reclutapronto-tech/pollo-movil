import { test, expect } from '@playwright/test';

test.describe('Authentication', () => {
  test('should show login page for unauthenticated users', async ({ page }) => {
    await page.goto('/');
    // AuthGuard should redirect or show login
    await expect(page).toHaveURL(/login|auth/);
  });

  test('should show sign out button when authenticated', async () => {
    // This test would need auth fixtures — skip with annotation for now
    test.skip(true, 'Requires auth fixtures');
  });
});
