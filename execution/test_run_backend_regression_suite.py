import importlib.util
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("run_backend_regression_suite.py")
REPO_ROOT = MODULE_PATH.parents[1]
SUPABASE_PROJECT_ROOT = REPO_ROOT / "infra"


def load_module():
    spec = importlib.util.spec_from_file_location("run_backend_regression_suite", MODULE_PATH)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class BackendRegressionSuiteRunnerTests(unittest.TestCase):
    def test_build_steps_includes_reset_by_default(self):
        module = load_module()

        steps = module.build_steps(skip_reset=False)

        self.assertEqual(
            steps,
            [
                ["supabase", "stop", "--project-id", "FieldsOps_ai", "--no-backup"],
                ["supabase", "stop", "--project-id", "infra", "--no-backup"],
                ["supabase", "start"],
                ["python3", "execution/seed_backend_test_data.py"],
                ["python3", "execution/test_sprint_1.py"],
                ["python3", "execution/test_schedule_flow.py"],
                ["python3", "execution/test_rls_validation.py"],
                ["python3", "execution/test_endpoint_contracts.py"],
            ],
        )

    def test_build_steps_can_skip_reset(self):
        module = load_module()

        steps = module.build_steps(skip_reset=True)

        self.assertEqual(
            steps,
            [
                ["supabase", "stop", "--project-id", "FieldsOps_ai"],
                ["supabase", "stop", "--project-id", "infra"],
                ["supabase", "start"],
                ["python3", "execution/seed_backend_test_data.py"],
                ["python3", "execution/test_sprint_1.py"],
                ["python3", "execution/test_schedule_flow.py"],
                ["python3", "execution/test_rls_validation.py"],
                ["python3", "execution/test_endpoint_contracts.py"],
            ],
        )

    def test_max_attempts_retries_reset_once(self):
        module = load_module()

        self.assertEqual(module.max_attempts_for(["supabase", "stop", "--project-id", "infra", "--no-backup"]), 1)
        self.assertEqual(module.max_attempts_for(["python3", "execution/test_sprint_1.py"]), 1)

    def test_working_directory_uses_infra_for_supabase_commands(self):
        module = load_module()

        self.assertEqual(module.working_directory_for(["supabase", "start"]), SUPABASE_PROJECT_ROOT)
        self.assertEqual(module.working_directory_for(["python3", "execution/test_sprint_1.py"]), REPO_ROOT)


if __name__ == "__main__":
    unittest.main()
