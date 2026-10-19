#!/usr/bin/env python3
"""
RLS validation test suite.

Two tiers of checks:
  1. Schema-level: Every tenant-owned table has RLS enabled and at least one policy.
  2. Data isolation: Company A's user cannot read Company B's data through
     PostgreSQL RLS policies. Uses SET LOCAL role + request.jwt.claims to
     simulate authenticated requests as specific users.

Requires seed.sql to have been applied (it creates Company A + Company B).
"""

import os
import subprocess
import sys

SUPABASE_URL = os.environ.get("SUPABASE_URL", "http://127.0.0.1:54321")

# ─── Constants ────────────────────────────────────────────────

# All tenant-owned tables that must have RLS enabled.
TABLES_TO_TEST = [
    "jobs",
    "tasks",
    "assignments",
    "clock_events",
    "photo_events",
    "task_events",
    "note_events",
    "media_assets",
    "ot_requests",
    "ot_approval_events",
    "alert_events",
    "shift_report_events",
    "expense_events",
    "schedule_shifts",
    "pto_requests",
]

# Company A (from seed.sql)
COMPANY_A_ID = "11111111-1111-1111-1111-111111111111"
WORKER_A_ID = "22222222-2222-2222-2222-222222222222"

# Company B (from seed.sql)
COMPANY_B_ID = "b0b0b0b0-b0b0-b0b0-b0b0-b0b0b0b0b0b0"
WORKER_B_ID = "b1b1b1b1-b1b1-b1b1-b1b1-b1b1b1b1b1b1"

# Tables with seeded data we can test isolation on.
# Maps table -> company_id column name (all use "company_id").
ISOLATION_TABLES = [
    "jobs",
    "tasks",
    "assignments",
    "clock_events",
    "schedule_shifts",
    "expense_events",
    "pto_requests",
]


# ─── Helpers ──────────────────────────────────────────────────

def run_sql(sql: str) -> str:
    """Execute SQL against local Supabase Postgres as superuser."""
    result = subprocess.run(
        ["docker", "exec", "-i", "supabase_db_infra",
         "psql", "-U", "postgres", "-d", "postgres", "-t", "-A", "-c", sql],
        capture_output=True, text=True, timeout=15,
    )
    return result.stdout.strip()


def run_sql_as_user(user_id: str, sql: str) -> str:
    """Execute SQL simulating an authenticated Supabase user via RLS.

    Sets the role to 'authenticated' and injects the user's JWT claims
    so that current_company_id() and auth.uid() resolve correctly.
    """
    # Build a minimal JWT claims JSON that auth.uid() and our helper
    # functions can read.  Supabase uses request.jwt.claims for this.
    wrapped = f"""
    BEGIN;
    SET LOCAL ROLE authenticated;
    SET LOCAL request.jwt.claims = '{{"sub": "{user_id}"}}';
    {sql}
    COMMIT;
    """
    result = subprocess.run(
        ["docker", "exec", "-i", "supabase_db_infra",
         "psql", "-U", "postgres", "-d", "postgres", "-t", "-A", "-c", wrapped],
        capture_output=True, text=True, timeout=15,
    )
    lines = [
        line.strip()
        for line in result.stdout.splitlines()
        if line.strip() and line.strip() not in {"BEGIN", "SET", "COMMIT"}
    ]
    return lines[-1] if lines else ""


# ─── Test Tier 1: Schema Checks ──────────────────────────────

def test_schema_checks():
    """Verify RLS is enabled and policies exist on all tenant tables."""
    print("=" * 60)
    print("TIER 1: SCHEMA CHECKS (RLS enabled + policies defined)")
    print("=" * 60)

    passed = 0
    failed = 0

    for table in TABLES_TO_TEST:
        rls_enabled = run_sql(
            f"SELECT relrowsecurity FROM pg_class WHERE relname = '{table}';"
        )
        if rls_enabled == "t":
            print(f"  ✓ {table}: RLS enabled")
            passed += 1
        else:
            print(f"  ✗ {table}: RLS NOT ENABLED")
            failed += 1

        policy_count = run_sql(
            f"SELECT count(*) FROM pg_policies WHERE tablename = '{table}';"
        )
        if int(policy_count or "0") > 0:
            print(f"  ✓ {table}: {policy_count} policies defined")
            passed += 1
        else:
            print(f"  ✗ {table}: NO policies defined")
            failed += 1

    return passed, failed


# ─── Test Tier 2: Data Isolation ──────────────────────────────

def test_data_isolation():
    """Verify Company A cannot read Company B's data and vice versa."""
    print()
    print("=" * 60)
    print("TIER 2: DATA ISOLATION (cross-company reads return 0 rows)")
    print("=" * 60)

    passed = 0
    failed = 0

    for table in ISOLATION_TABLES:
        # ── Worker A should see Company A data, NOT Company B data ──
        count_own = run_sql_as_user(
            WORKER_A_ID,
            f"SELECT count(*) FROM {table} WHERE company_id = '{COMPANY_A_ID}';",
        )
        count_cross = run_sql_as_user(
            WORKER_A_ID,
            f"SELECT count(*) FROM {table} WHERE company_id = '{COMPANY_B_ID}';",
        )

        own_count = int(count_own or "0")
        cross_count = int(count_cross or "0")

        if own_count > 0:
            print(f"  ✓ {table}: Worker A sees {own_count} own rows")
            passed += 1
        else:
            print(f"  ✗ {table}: Worker A sees 0 own rows (expected > 0)")
            failed += 1

        if cross_count == 0:
            print(f"  ✓ {table}: Worker A sees 0 cross-company rows (isolated)")
            passed += 1
        else:
            print(f"  ✗ {table}: Worker A sees {cross_count} cross-company rows (LEAK!)")
            failed += 1

        # ── Worker B should see Company B data, NOT Company A data ──
        count_own_b = run_sql_as_user(
            WORKER_B_ID,
            f"SELECT count(*) FROM {table} WHERE company_id = '{COMPANY_B_ID}';",
        )
        count_cross_b = run_sql_as_user(
            WORKER_B_ID,
            f"SELECT count(*) FROM {table} WHERE company_id = '{COMPANY_A_ID}';",
        )

        own_count_b = int(count_own_b or "0")
        cross_count_b = int(count_cross_b or "0")

        if own_count_b > 0:
            print(f"  ✓ {table}: Worker B sees {own_count_b} own rows")
            passed += 1
        else:
            print(f"  ✗ {table}: Worker B sees 0 own rows (expected > 0)")
            failed += 1

        if cross_count_b == 0:
            print(f"  ✓ {table}: Worker B sees 0 cross-company rows (isolated)")
            passed += 1
        else:
            print(f"  ✗ {table}: Worker B sees {cross_count_b} cross-company rows (LEAK!)")
            failed += 1

    return passed, failed


# ─── Main ─────────────────────────────────────────────────────

def main():
    schema_passed, schema_failed = test_schema_checks()
    isolation_passed, isolation_failed = test_data_isolation()

    total_passed = schema_passed + isolation_passed
    total_failed = schema_failed + isolation_failed

    print()
    print("=" * 60)
    print(f"RESULTS: {total_passed} passed, {total_failed} failed")
    print(f"  Schema checks:   {schema_passed} passed, {schema_failed} failed")
    print(f"  Data isolation:  {isolation_passed} passed, {isolation_failed} failed")
    print("=" * 60)

    return total_failed == 0


if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1)
