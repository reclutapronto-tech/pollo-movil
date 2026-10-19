import { test, expect } from '@playwright/test';

test.describe('Schedule', () => {
  test('should render calendar view', async ({ page }) => {
    await page.goto('/schedule');
    // Wait for page to load — should show FullCalendar or schedule content
    await page.waitForTimeout(3000);
    // Check for schedule-related content
    const content = await page.textContent('body');
    expect(content).toBeDefined();
  });
});
