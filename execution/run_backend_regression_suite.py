#!/usr/bin/env python3
"""
Backend regression suite runner.

Works in both local dev (with running Supabase) and CI (fresh start).
Steps:
  1. Stop any running Supabase instances (non-fatal — may not be running)
  2. Start Supabase (pulls images + applies migrations)
  3. Seed test data
  4. Run test suites
  5. (Optional) Run RLS validation
  6. Cleanup test-generated data (non-fatal)
"""
import argparse
import json
import os
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
SUPABASE_PROJECT_ROOT = REPO_ROOT / "infra"

# Commands where a non-zero exit code is acceptable (e.g. stopping
# a Supabase instance that isn't running).  These are logged as
# warnings but do not abort the suite.
SOFT_FAIL_PREFIXES = [
    ["supabase", "stop"],
]


def build_steps(skip_reset: bool) -> list[list[str]]:
    if skip_reset:
        return [
            ["supabase", "stop", "--project-id", "FieldsOps_ai"],
            ["supabase", "stop", "--project-id", "infra"],
            ["supabase", "start"],
            ["python3", "execution/seed_backend_test_data.py"],
            ["python3", "execution/test_sprint_1.py"],
            ["python3", "execution/test_schedule_flow.py"],
            ["python3", "execution/test_rls_validation.py"],
            ["python3", "execution/test_endpoint_contracts.py"],
        ]
    return [
        ["supabase", "stop", "--project-id", "FieldsOps_ai", "--no-backup"],
        ["supabase", "stop", "--project-id", "infra", "--no-backup"],
        ["supabase", "start"],
        ["python3", "execution/seed_backend_test_data.py"],
        ["python3", "execution/test_sprint_1.py"],
        ["python3", "execution/test_schedule_flow.py"],
        ["python3", "execution/test_rls_validation.py"],
        ["python3", "execution/test_endpoint_contracts.py"],
    ]


def is_soft_fail(command: list[str]) -> bool:
    """Return True if this command's failure should be treated as a warning."""
    return any(
        command[: len(prefix)] == prefix
        for prefix in SOFT_FAIL_PREFIXES
    )


def max_attempts_for(command: list[str]) -> int:
    """How many times to retry a command before giving up."""
    # supabase start can be flaky in CI (Docker pull timeouts)
    if command and command[0] == "supabase" and "start" in command:
        return 2
    return 1


def working_directory_for(command: list[str]) -> Path:
    if command and command[0] == "supabase":
        return SUPABASE_PROJECT_ROOT
    return REPO_ROOT


def log_event(event: str, **payload: object) -> None:
    line = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "event": event,
        **payload,
    }
    print(json.dumps(line), flush=True)


def run_step(command: list[str]) -> int:
    log_event("step_start", command=command)
    completed = subprocess.run(command, cwd=working_directory_for(command))
    log_event("step_end", command=command, returncode=completed.returncode)
    return completed.returncode


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run the local backend regression suite.")
    parser.add_argument(
        "--skip-reset",
        action="store_true",
        help="Skip `supabase db reset` and run only the verifier.",
    )
    return parser.parse_args()


def cleanup_test_data() -> None:
    """Delete test-generated data from transactional tables, preserving seed data.

    Uses docker exec psql against the local Supabase container.
    Failures are non-fatal so they never mask real test results.
    """
    tables = [
        "clock_events",
        "photo_events",
        "task_events",
        "note_events",
        "expense_events",
        "ot_requests",
        "schedule_shifts",
    ]
    sql = "TRUNCATE " + ", ".join(tables) + " CASCADE;"
    cmd = [
        "docker", "exec", "-i", "supabase_db_infra",
        "psql", "-U", "postgres", "-d", "postgres", "-c", sql,
    ]
    log_event("cleanup_start", tables=tables)
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        if result.returncode == 0:
            log_event("cleanup_done")
        else:
            log_event("cleanup_soft_fail", returncode=result.returncode,
                      stderr=result.stderr.strip())
    except Exception as exc:
        log_event("cleanup_soft_fail", error=str(exc))


def main() -> int:
    args = parse_args()
    steps = build_steps(skip_reset=args.skip_reset)
    log_event("suite_start", steps=steps, ci=bool(os.environ.get("CI")))

    suite_rc = 0
    try:
        for command in steps:
            attempts = max_attempts_for(command)
            returncode = 1  # default in case loop doesn't execute
            for attempt in range(1, attempts + 1):
                returncode = run_step(command)
                if returncode == 0:
                    break
                if attempt < attempts:
                    log_event("step_retry", command=command, attempt=attempt + 1)
                    time.sleep(5)

            if returncode != 0:
                if is_soft_fail(command):
                    log_event("step_soft_fail", command=command, returncode=returncode)
                    # Continue — supabase stop failing is expected in CI
                else:
                    log_event("suite_failed", failed_command=command, returncode=returncode)
                    suite_rc = returncode
                    return suite_rc

        log_event("suite_passed")
        return suite_rc
    finally:
        cleanup_test_data()


if __name__ == "__main__":
    sys.exit(main())
