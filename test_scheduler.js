const { chromium } = require("playwright");

async function testScheduler() {
  const browser = await chromium.launch();
  const page = await browser.newPage();

  try {
    console.log("🌐 Navigating to login page...");
    await page.goto("http://127.0.0.1:3000/schedule", {
      waitUntil: "networkidle",
    });

    // Wait for login form and fill credentials
    console.log("🔐 Looking for login form...");
    await page.waitForSelector('input[type="email"]', { timeout: 5000 });

    console.log("📝 Entering supervisor credentials...");
    await page.fill('input[type="email"]', "supervisor@test.com");
    await page.fill('input[type="password"]', "password123");

    // Click sign-in button
    const signInBtn =
      (await page.$('button:has-text("Sign In")')) ||
      (await page.$('button:has-text("sign in")')) ||
      (await page.$('button:has-text("SignIn")')) ||
      (await page
        .locator("button")
        .filter({ hasText: /sign in/i })
        .first());

    console.log("🔘 Clicking sign-in button...");
    await signInBtn.click();

    // Wait for redirect to schedule page after login
    console.log("⏳ Waiting for schedule page to load...");
    await page.waitForNavigation({ waitUntil: "networkidle", timeout: 10000 });

    // Check for FullCalendar presence
    console.log("🔍 Checking for FullCalendar component...");
    const calendarExists = (await page.locator(".fc").count()) > 0;
    console.log(`   FullCalendar rendered: ${calendarExists ? "✅" : "❌"}`);

    // Check for worker sidebar
    console.log("🔍 Checking for worker sidebar...");
    const sidebarExists = (await page.locator("aside").count()) > 0;
    console.log(`   Sidebar exists: ${sidebarExists ? "✅" : "❌"}`);

    // Check for search input
    const searchInput =
      (await page.locator('input[type="search"]').count()) > 0;
    console.log(`   Worker search input: ${searchInput ? "✅" : "❌"}`);

    // Check for external worker elements
    const workerElements = await page.locator(".external-worker").count();
    console.log(`   External worker elements found: ${workerElements || "❌"}`);

    // Check for resource timeline view
    const timelineView =
      (await page.locator(".fc-resource-timeline").count()) > 0;
    console.log(`   Resource timeline view: ${timelineView ? "✅" : "❌"}`);

    // Try to find view mode buttons
    const viewButtons = await page.locator("button").count();
    console.log(`   View control buttons found: ${viewButtons}`);

    // Additional checks - header and main content
    console.log("🔍 Checking for schedule page structure...");
    const hasHeader = (await page.locator("h1, h2").count()) > 0;
    console.log(`   Page header found: ${hasHeader ? "✅" : "❌"}`);

    // Take a screenshot for visual inspection
    await page.screenshot({ path: "/tmp/scheduler_page.png" });
    console.log("📸 Screenshot saved to /tmp/scheduler_page.png");

    console.log("\n✨ Scheduler UI test complete!");
  } catch (error) {
    console.error("❌ Error during test:", error.message);
  } finally {
    await browser.close();
  }
}

testScheduler();
