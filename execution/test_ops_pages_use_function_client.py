from pathlib import Path
import unittest


REPO_ROOT = Path(__file__).resolve().parents[1]
EXPENSES_PAGE = REPO_ROOT / "apps/fieldops_web/src/app/expenses/page.tsx"
PTO_PAGE = REPO_ROOT / "apps/fieldops_web/src/app/pto/page.tsx"
COST_CODES_PAGE = REPO_ROOT / "apps/fieldops_web/src/app/cost-codes/page.tsx"


class OpsPagesFunctionClientTests(unittest.TestCase):
    def test_expenses_page_uses_shared_function_client(self) -> None:
        source = EXPENSES_PAGE.read_text()
        self.assertIn('from "@/lib/function-client"', source)
        self.assertIn("callFunctionJson", source)

    def test_pto_page_uses_shared_function_client(self) -> None:
        source = PTO_PAGE.read_text()
        self.assertIn('from "@/lib/function-client"', source)
        self.assertIn("callFunctionJson", source)
        self.assertNotIn("supabase.auth.getSession()", source)

    def test_cost_codes_page_uses_shared_function_client(self) -> None:
        source = COST_CODES_PAGE.read_text()
        self.assertIn('from "@/lib/function-client"', source)
        self.assertIn("callFunctionJson", source)
        self.assertNotIn("Missing session", source)


if __name__ == "__main__":
    unittest.main()
