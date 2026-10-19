from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from scripts.sync_runtime_env import is_hosted_supabase_url, sync_repo_env


class SyncRuntimeEnvTests(unittest.TestCase):
    def test_sync_repo_env_writes_web_and_mobile_config(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "apps" / "fieldops_web").mkdir(parents=True)
            (root / "apps" / "fieldops_mobile").mkdir(parents=True)
            (root / ".env").write_text(
                "\n".join(
                    [
                        'SUPABASE_URL="https://example.supabase.co"',
                        'SUPABASE_ANON_KEY="anon-key"',
                        'SENTRY_DSN="mobile-dsn"',
                        'NEXT_PUBLIC_POSTHOG_KEY="phc_123"',
                        'NEXT_PUBLIC_POSTHOG_HOST="https://app.posthog.com"',
                        "",
                    ]
                )
            )

            result = sync_repo_env(root)

            self.assertTrue(result.hosted)
            self.assertEqual(result.supabase_url, "https://example.supabase.co")

            web_contents = (root / "apps" / "fieldops_web" / ".env.local").read_text()
            self.assertIn("NEXT_PUBLIC_SUPABASE_URL=https://example.supabase.co", web_contents)
            self.assertIn("NEXT_PUBLIC_SUPABASE_ANON_KEY=anon-key", web_contents)
            self.assertIn("NEXT_PUBLIC_POSTHOG_KEY=phc_123", web_contents)

            mobile_payload = json.loads(
                (root / "apps" / "fieldops_mobile" / "env" / "staging.json").read_text()
            )
            self.assertEqual(
                mobile_payload,
                {
                    "SUPABASE_URL": "https://example.supabase.co",
                    "SUPABASE_ANON_KEY": "anon-key",
                    "SENTRY_DSN": "mobile-dsn",
                },
            )

    def test_hosted_detection_flags_local_urls(self) -> None:
        self.assertFalse(is_hosted_supabase_url("http://127.0.0.1:54321"))
        self.assertFalse(is_hosted_supabase_url("http://localhost:54321"))
        self.assertTrue(is_hosted_supabase_url("https://project.supabase.co"))


if __name__ == "__main__":
    unittest.main()
