import importlib.util
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("seed_backend_test_data.py")


def load_module():
    spec = importlib.util.spec_from_file_location("seed_backend_test_data", MODULE_PATH)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class SeedBackendTestDataTests(unittest.TestCase):
    def test_build_seed_command_targets_resolved_local_supabase_db_container(self):
        module = load_module()

        self.assertEqual(
            module.build_seed_command("supabase_db_FieldsOps_ai"),
            [
                "docker",
                "exec",
                "-i",
                "supabase_db_FieldsOps_ai",
                "psql",
                "-U",
                "postgres",
                "-d",
                "postgres",
            ],
        )

    def test_resolve_db_container_name_prefers_supabase_db_prefix(self):
        module = load_module()

        container_name = module.resolve_db_container_name(
            [
                "supabase_auth_FieldsOps_ai",
                "supabase_db_FieldsOps_ai",
                "supabase_storage_FieldsOps_ai",
            ]
        )

        self.assertEqual(container_name, "supabase_db_FieldsOps_ai")


if __name__ == "__main__":
    unittest.main()
