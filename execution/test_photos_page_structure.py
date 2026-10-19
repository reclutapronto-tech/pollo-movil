from pathlib import Path
import unittest


REPO_ROOT = Path(__file__).resolve().parents[1]
PHOTOS_PAGE = REPO_ROOT / "apps/fieldops_web/src/app/photos/page.tsx"
PROJECT_BROWSER = REPO_ROOT / "apps/fieldops_web/src/components/photos/project-browser.tsx"
WORKSPACE_TABS = REPO_ROOT / "apps/fieldops_web/src/components/photos/project-workspace-tabs.tsx"
TIMELINE_PANEL = REPO_ROOT / "apps/fieldops_web/src/components/photos/photo-timeline-panel.tsx"
MAP_PANEL = REPO_ROOT / "apps/fieldops_web/src/components/photos/photo-map-panel.tsx"


class PhotosPageStructureTests(unittest.TestCase):
    def test_photo_workspace_components_exist(self) -> None:
        self.assertTrue(PROJECT_BROWSER.exists())
        self.assertTrue(WORKSPACE_TABS.exists())
        self.assertTrue(TIMELINE_PANEL.exists())
        self.assertTrue(MAP_PANEL.exists())

    def test_photos_page_uses_project_browser_and_workspace_tabs(self) -> None:
        source = PHOTOS_PAGE.read_text()
        self.assertIn('from "@/components/photos/project-browser"', source)
        self.assertIn('from "@/components/photos/project-workspace-tabs"', source)
        self.assertIn("<ProjectBrowser", source)
        self.assertIn("<ProjectWorkspaceTabs", source)

    def test_photos_page_keeps_timeline_and_map_in_page(self) -> None:
        source = PHOTOS_PAGE.read_text()
        self.assertNotIn('href={`/timeline?job_id=${encodeURIComponent(jobId)}`}', source)
        self.assertNotIn('href={`/map?job_id=${encodeURIComponent(jobId)}`}', source)
        self.assertIn('activeTab === "timeline"', source)
        self.assertIn('activeTab === "map"', source)


if __name__ == "__main__":
    unittest.main()
