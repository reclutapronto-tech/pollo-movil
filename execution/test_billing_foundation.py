from pathlib import Path
import unittest


REPO_ROOT = Path(__file__).resolve().parents[1]


class BillingFoundationTests(unittest.TestCase):
    def test_billing_migration_adds_company_billing_columns(self) -> None:
        migration = (REPO_ROOT / "infra/supabase/migrations/20260410010000_company_billing_and_ownership.sql").read_text()
        owner_migration = (REPO_ROOT / "infra/supabase/migrations/20260411010000_owner_role_and_demo_billing.sql").read_text()
        self.assertIn("stripe_subscription_id", migration)
        self.assertIn("billing_email", migration)
        self.assertIn("billing_plan", migration)
        self.assertIn("billing_mode", owner_migration)

    def test_billing_portal_function_exists_and_uses_stripe_portal(self) -> None:
        source = (REPO_ROOT / "infra/supabase/functions/billing_portal/index.ts").read_text()
        self.assertIn("billingPortal.sessions.create", source)
        self.assertIn('Only owners or admins can manage billing', source)
        self.assertIn('mode: "demo"', source)

    def test_stripe_webhook_function_exists_and_updates_company_billing_state(self) -> None:
        source = (REPO_ROOT / "infra/supabase/functions/stripe_webhook/index.ts").read_text()
        self.assertIn('customer.subscription.updated', source)
        self.assertIn('checkout.session.completed', source)
        self.assertIn('.update({', source)
        self.assertIn('payment_status', source)

    def test_tenant_billing_page_exists(self) -> None:
        source = (REPO_ROOT / "apps/fieldops_web/src/app/settings/billing/page.tsx").read_text()
        self.assertIn("Manage Billing", source)
        self.assertIn("payment_status", source)
        self.assertIn("billing_mode", source)

    def test_sidebar_links_to_billing_page(self) -> None:
        source = (REPO_ROOT / "apps/fieldops_web/src/components/sidebar.tsx").read_text()
        self.assertIn('/settings/billing', source)


if __name__ == "__main__":
    unittest.main()
