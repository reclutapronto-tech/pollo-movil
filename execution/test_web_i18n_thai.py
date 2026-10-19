from pathlib import Path
import unittest


REPO_ROOT = Path(__file__).resolve().parents[1]
I18N_FILE = REPO_ROOT / "apps/fieldops_web/src/lib/i18n.tsx"
SIDEBAR_FILE = REPO_ROOT / "apps/fieldops_web/src/components/sidebar.tsx"


class WebI18nThaiTests(unittest.TestCase):
    def test_locale_union_includes_thai(self) -> None:
        source = I18N_FILE.read_text()
        self.assertIn('export type Locale = "en" | "es" | "th";', source)

    def test_translations_define_thai_language_labels(self) -> None:
        source = I18N_FILE.read_text()
        self.assertIn("translations.th =", source)
        self.assertIn('thai: "ไทย"', source)

    def test_sidebar_exposes_thai_in_language_picker(self) -> None:
        source = SIDEBAR_FILE.read_text()
        self.assertIn('option value="th"', source)


if __name__ == "__main__":
    unittest.main()
