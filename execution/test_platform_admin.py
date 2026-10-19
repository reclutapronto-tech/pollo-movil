from pathlib import Path
import unittest


REPO_ROOT = Path(__file__).resolve().parents[1]
PLATFORM_ADMIN_FN = REPO_ROOT / "infra/supabase/functions/platform_admin/index.ts"
COMPANY_DETAIL_PAGE = REPO_ROOT / "apps/fieldops_admin/src/app/companies/[id]/page.tsx"
NEW_COMPANY_PAGE = REPO_ROOT / "apps/fieldops_admin/src/app/companies/new/page.tsx"


class PlatformAdminContractTests(unittest.TestCase):
    def test_list_companies_uses_summary_view(self) -> None:
        source = PLATFORM_ADMIN_FN.read_text()
        self.assertIn('.from("company_summary")', source)

    def test_company_detail_posts_toggle_company(self) -> None:
        source = COMPANY_DETAIL_PAGE.read_text()
        self.assertIn('action: "toggle_company"', source)
        self.assertNotIn('action: "update_company"', source)

    def test_new_company_page_posts_admin_name(self) -> None:
        source = NEW_COMPANY_PAGE.read_text()
        self.assertIn("owner_name: ownerName", source)
        self.assertIn("owner_email: ownerEmail", source)
        self.assertNotIn("admin_full_name: adminName", source)

    def test_create_company_assigns_owner_role(self) -> None:
        source = PLATFORM_ADMIN_FN.read_text()
        self.assertIn('role: OWNER_ROLE', source)
        self.assertIn('const owner_email = payload.owner_email || payload.admin_email', source)
        self.assertIn('const owner_name = payload.owner_name || payload.admin_name', source)

    def test_company_detail_reads_audit_logs_payload(self) -> None:
        source = COMPANY_DETAIL_PAGE.read_text()
        self.assertIn("auditData.audit_logs", source)

    def test_create_invite_uses_existing_invite_schema(self) -> None:
        source = PLATFORM_ADMIN_FN.read_text()
        self.assertIn("created_by: platformAdmin.id", source)
        self.assertNotIn("invited_by: user.id", source)
        self.assertNotIn("claimed: false", source)

    def test_claim_invite_does_not_require_existing_platform_admin(self) -> None:
        source = PLATFORM_ADMIN_FN.read_text()
        self.assertIn('const allowUnauthedClaim = req.method === "POST" && payload?.action === "claim_invite"', source)

    def test_admins_page_uses_claim_url_response(self) -> None:
        source = (REPO_ROOT / "apps/fieldops_admin/src/app/admins/page.tsx").read_text()
        self.assertIn("data.claim_url", source)
        self.assertNotIn("data.invite_link", source)


if __name__ == "__main__":
    unittest.main()
