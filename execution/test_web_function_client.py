from pathlib import Path
import unittest


REPO_ROOT = Path(__file__).resolve().parents[1]
FUNCTION_CLIENT = REPO_ROOT / "apps/fieldops_web/src/lib/function-client.ts"


class WebFunctionClientTests(unittest.TestCase):
    def test_function_client_exists(self) -> None:
        self.assertTrue(FUNCTION_CLIENT.exists())

    def test_function_client_fetches_session_token(self) -> None:
        source = FUNCTION_CLIENT.read_text()
        self.assertIn("supabase.auth.getSession()", source)
        self.assertIn("Missing session", source)

    def test_function_client_parses_json_safely(self) -> None:
        source = FUNCTION_CLIENT.read_text()
        self.assertIn("response.text()", source)
        self.assertIn("JSON.parse", source)

    def test_function_client_sets_authorization_header(self) -> None:
        source = FUNCTION_CLIENT.read_text()
        self.assertIn("Authorization", source)
        self.assertIn("functions/v1", source)


if __name__ == "__main__":
    unittest.main()
