from pathlib import Path
import unittest


REPO_ROOT = Path(__file__).resolve().parents[1]
OVERTIME_PAGE = REPO_ROOT / "apps/fieldops_web/src/app/overtime/page.tsx"
OT_FUNCTION = REPO_ROOT / "infra/supabase/functions/ot/index.ts"


class OvertimePageContractTests(unittest.TestCase):
    def test_overtime_page_uses_shared_function_client(self) -> None:
        source = OVERTIME_PAGE.read_text()
        self.assertIn('from "@/lib/function-client"', source)
        self.assertIn('callFunctionJson', source)

    def test_overtime_page_no_longer_queries_ot_requests_directly(self) -> None:
        source = OVERTIME_PAGE.read_text()
        self.assertNotIn('.from("ot_requests")', source)

    def test_ot_function_supports_offset_and_limit(self) -> None:
        source = OT_FUNCTION.read_text()
        self.assertIn('const offset = Number(url.searchParams.get("offset") || "0")', source)
        self.assertIn('const limit = Number(url.searchParams.get("limit") || "50")', source)
        self.assertIn(".range(safeOffset, safeOffset + safeLimit - 1)", source)


if __name__ == "__main__":
    unittest.main()
