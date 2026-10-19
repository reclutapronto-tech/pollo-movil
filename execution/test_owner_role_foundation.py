from pathlib import Path
import unittest


REPO_ROOT = Path(__file__).resolve().parents[1]


class OwnerRoleFoundationTests(unittest.TestCase):
    def test_foundation_schema_defines_owner_role(self) -> None:
        source = (REPO_ROOT / "infra/supabase/migrations/20260403000000_foundation_tables.sql").read_text()
        self.assertIn("CREATE TYPE user_role AS ENUM ('owner', 'admin', 'supervisor', 'foreman', 'worker');", source)

    def test_owner_role_migration_exists_for_live_projects(self) -> None:
        source = (REPO_ROOT / "infra/supabase/migrations/20260411010000_owner_role_and_demo_billing.sql").read_text()
        self.assertIn("ADD VALUE IF NOT EXISTS 'owner'", source)
        self.assertIn("billing_mode", source)

    def test_staff_page_includes_owner_role_and_management_gate(self) -> None:
        source = (REPO_ROOT / "apps/fieldops_web/src/app/settings/staff/page.tsx").read_text()
        self.assertIn('{ value: "owner"', source)
        self.assertIn("isManagementRole", source)
        self.assertIn("Only the company owner can assign or edit the owner role.", source)

    def test_web_role_helpers_define_management_roles(self) -> None:
        source = (REPO_ROOT / "apps/fieldops_web/src/lib/roles.ts").read_text()
        self.assertIn('export const OWNER_ROLE = "owner";', source)
        self.assertIn("MANAGEMENT_ROLES", source)

    def test_invites_allow_owner_and_owner_can_invite_admins(self) -> None:
        source = (REPO_ROOT / "infra/supabase/functions/invites/index.ts").read_text()
        self.assertIn("Only owners, admins, or supervisors can send invites", source)
        self.assertIn('["admin", "supervisor", "foreman", "worker"]', source)


class OwnerRoleRLSPolicyTests(unittest.TestCase):
    """Verify RLS policies enforce owner role boundaries at the SQL level."""

    def test_admin_user_update_policy_blocks_owner_role_elevation(self) -> None:
        # The WITH CHECK clause must prevent an admin from setting role = 'owner'
        # on any user. This is the critical privilege escalation guard.
        source = (REPO_ROOT / "infra/supabase/migrations/20260411010000_owner_role_and_demo_billing.sql").read_text()
        self.assertIn("Admin user update", source)
        # Admin path must have: role <> 'owner' guard so admin can't touch owner-role users
        self.assertIn("role <> 'owner'", source)
        # Owner path must exist with no such restriction (owner can manage all)
        self.assertIn("current_user_role() = 'owner'", source)

    def test_billing_portal_demo_guard_is_inside_serve(self) -> None:
        # The demo mode guard must appear BEFORE Stripe customer creation logic,
        # not as dead code after the serve() callback closes.
        source = (REPO_ROOT / "infra/supabase/functions/billing_portal/index.ts").read_text()
        demo_guard_pos = source.index('billing_mode === "demo"')
        stripe_customer_pos = source.index("stripe.customers.create")
        self.assertLess(
            demo_guard_pos,
            stripe_customer_pos,
            "Demo mode guard must appear before stripe.customers.create to prevent hitting Stripe in demo mode",
        )

    def test_phone_invite_creates_user_record(self) -> None:
        # Phone invites must insert into the users table, not just return a fake 201.
        source = (REPO_ROOT / "infra/supabase/functions/invites/index.ts").read_text()
        self.assertIn("auth.admin.createUser", source)
        self.assertIn("is_active: false", source)
        self.assertIn("authUser.user.id", source)


if __name__ == "__main__":
    unittest.main()
