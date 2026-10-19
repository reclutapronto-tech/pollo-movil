import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
I18N_FILE = ROOT / "apps/fieldops_web/src/lib/i18n.tsx"


class WebI18nCoverageTest(unittest.TestCase):
    def test_remaining_web_pages_use_i18n(self) -> None:
        targets = [
            ROOT / "apps/fieldops_web/src/app/onboarding/page.tsx",
            ROOT / "apps/fieldops_web/src/app/settings/page.tsx",
            ROOT / "apps/fieldops_web/src/app/settings/staff/page.tsx",
        ]

        for path in targets:
            source = path.read_text()
            self.assertIn('useI18n', source, f"{path.name} should import/use the locale hook")
            self.assertIn('t("', source, f"{path.name} should render translated strings")

    def test_translation_map_contains_remaining_web_sections(self) -> None:
        source = I18N_FILE.read_text()

        for key in ("onboardingPage", "settingsPage", "staffPage"):
            self.assertGreaterEqual(
                source.count(f"{key}:"),
                2,
                f"{key} should exist in both English and Spanish translation trees",
            )


if __name__ == "__main__":
    unittest.main()
