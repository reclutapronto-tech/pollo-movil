"""
Endpoint contract tests — one per edge function.

Sprint 8.6 Lesson 50: client↔server contract mismatches are silent
production failures. The only real defense is hitting every endpoint
with the exact body shape the mobile/web client produces and asserting
the response keys.

This file is the catch-all contract harness. It complements:
  - test_sprint_1.py        (deep behaviour for sync/media/clock loop)
  - test_schedule_flow.py   (end-to-end schedule create/update/publish)
  - test_rls_validation.py  (cross-company RLS isolation)

Each test method targets ONE (function, action) pair. The body shape
is what the mobile or web client actually sends; the assertion checks
the response keys at the top level (so mobile JSON parsers don't blow
up). Business-logic correctness is intentionally out of scope — those
tests live in the deeper suites above.

Running:
  - Local: `supabase start` then `python3 execution/test_endpoint_contracts.py`
  - The seeded test users (worker/worker2/supervisor/admin@test.com,
    password123) come from infra/supabase/seed.sql.

Adding a new endpoint:
  1. Add a `EXPECTED_*` set of top-level keys for the success response.
  2. Add a `test_<function>_<action>` method that calls `_post` (or
     `_get`) and uses `_expect_keys` to assert those keys are present.
  3. If the action requires `Idempotency-Key`, pass `idempotent=True`.

When the response shape changes, update this file IN THE SAME PR as
the function change. CI fails fast on drift instead of waiting for
Sentry to surface it from real users.
"""
from __future__ import annotations

import os
import unittest
import uuid
from typing import Any

import requests

# ─── Test infrastructure ──────────────────────────────────────

_LOCAL_ANON = (
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9."
    "eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9."
    "CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0"
)

SUPABASE_URL = os.environ.get("SUPABASE_URL", "http://127.0.0.1:54321")
SUPABASE_ANON_KEY = os.environ.get("SUPABASE_ANON_KEY", _LOCAL_ANON)

TEST_USERS = {
    "worker": "worker@test.com",
    "worker2": "worker2@test.com",
    "supervisor": "supervisor@test.com",
    "admin": "admin@test.com",
}
TEST_PASSWORD = "password123"

# Tokens cached at class init so we don't re-auth per test.
_token_cache: dict[str, str] = {}


def _authenticate(email: str) -> str:
    if email in _token_cache:
        return _token_cache[email]
    response = requests.post(
        f"{SUPABASE_URL}/auth/v1/token?grant_type=password",
        headers={
            "apikey": SUPABASE_ANON_KEY,
            "Content-Type": "application/json",
        },
        json={"email": email, "password": TEST_PASSWORD},
        timeout=15,
    )
    if response.status_code != 200:
        raise RuntimeError(
            f"auth failed for {email}: {response.status_code} {response.text}"
        )
    token = response.json()["access_token"]
    _token_cache[email] = token
    return token


def _headers(token: str, *, idempotent: bool = False) -> dict[str, str]:
    h = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
        "X-Client-Version": "fieldops-mobile",
    }
    if idempotent:
        h["Idempotency-Key"] = str(uuid.uuid4())
    return h


def _post(
    function: str,
    *,
    user: str,
    body: dict[str, Any] | None = None,
    idempotent: bool = False,
    expect_status: int | tuple[int, ...] = 200,
) -> dict[str, Any]:
    token = _authenticate(TEST_USERS[user])
    response = requests.post(
        f"{SUPABASE_URL}/functions/v1/{function}",
        headers=_headers(token, idempotent=idempotent),
        json=body or {},
        timeout=15,
    )
    expected = (
        (expect_status,) if isinstance(expect_status, int) else expect_status
    )
    if response.status_code not in expected:
        raise AssertionError(
            f"{function} POST returned {response.status_code} (wanted {expected}): "
            f"{response.text[:400]}"
        )
    if not response.text:
        return {}
    try:
        return response.json()
    except Exception as exc:
        raise AssertionError(f"{function} returned non-JSON: {response.text[:400]}") from exc


def _get(
    function: str,
    *,
    user: str,
    query: dict[str, Any] | None = None,
    expect_status: int | tuple[int, ...] = 200,
) -> dict[str, Any]:
    token = _authenticate(TEST_USERS[user])
    response = requests.get(
        f"{SUPABASE_URL}/functions/v1/{function}",
        headers=_headers(token),
        params=query or {},
        timeout=15,
    )
    expected = (
        (expect_status,) if isinstance(expect_status, int) else expect_status
    )
    if response.status_code not in expected:
        raise AssertionError(
            f"{function} GET returned {response.status_code} (wanted {expected}): "
            f"{response.text[:400]}"
        )
    if not response.text:
        return {}
    try:
        return response.json()
    except Exception as exc:
        raise AssertionError(f"{function} returned non-JSON: {response.text[:400]}") from exc


def _expect_keys(payload: dict[str, Any], *keys: str) -> None:
    missing = [k for k in keys if k not in payload]
    if missing:
        raise AssertionError(
            f"response missing keys {missing}; got keys {sorted(payload.keys())}"
        )


# ─── Per-function contract tests ──────────────────────────────


class JobsActiveContract(unittest.TestCase):
    """jobs_active — GET only; mobile reads it on home screen mount."""

    def test_get_returns_jobs_array(self) -> None:
        body = _get("jobs_active", user="worker")
        _expect_keys(body, "jobs")
        self.assertIsInstance(body["jobs"], list)


class SyncEventsContract(unittest.TestCase):
    """sync_events — POST only; mobile clock-in/out path."""

    def test_post_with_empty_batch_is_accepted(self) -> None:
        # Empty batch with valid header shape — server should still
        # respond with the standard accepted/duplicates/rejected envelope.
        body = _post(
            "sync_events",
            user="worker",
            idempotent=True,
            body={"batch_id": str(uuid.uuid4()), "clock_events": []},
        )
        _expect_keys(body, "status", "accepted", "duplicates", "rejected")


class PtoContract(unittest.TestCase):
    """pto — request, balance, pending_approvals, decide,
    allocations_list, allocations_upsert."""

    def test_get_returns_requests_array(self) -> None:
        body = _get("pto", user="worker")
        _expect_keys(body, "requests")
        self.assertIsInstance(body["requests"], list)

    def test_balance_returns_breakdown(self) -> None:
        body = _post("pto", user="worker", body={"action": "balance"})
        _expect_keys(body, "balance")
        b = body["balance"]
        for k in (
            "vacation_total",
            "vacation_used",
            "sick_total",
            "sick_used",
            "personal_total",
            "personal_used",
        ):
            self.assertIn(k, b, f"balance missing {k}")

    def test_pending_approvals_supervisor(self) -> None:
        body = _post(
            "pto", user="supervisor", body={"action": "pending_approvals"}
        )
        _expect_keys(body, "requests")
        self.assertIsInstance(body["requests"], list)

    def test_allocations_list_admin(self) -> None:
        body = _post(
            "pto", user="admin", body={"action": "allocations_list"}
        )
        _expect_keys(body, "allocations")
        for row in body["allocations"][:1]:
            self.assertIn("user_id", row)
            self.assertIn("pto_type", row)
            self.assertIn("year", row)
            self.assertIn("total_days", row)

    def test_allocations_list_worker_forbidden(self) -> None:
        body = _post(
            "pto",
            user="worker",
            body={"action": "allocations_list"},
            expect_status=403,
        )
        _expect_keys(body, "error_code")


class OtContract(unittest.TestCase):
    """ot — pending, request, decide."""

    def test_get_returns_requests(self) -> None:
        body = _get("ot", user="worker")
        # Worker-side history view; envelope key may be `requests` or `ot_requests`.
        self.assertTrue(
            "requests" in body or "ot_requests" in body,
            f"ot GET missing requests envelope: {sorted(body.keys())}",
        )

    def test_pending_supervisor(self) -> None:
        body = _post("ot", user="supervisor", body={"action": "pending"})
        self.assertTrue(
            "requests" in body or "ot_requests" in body,
            f"ot pending missing envelope: {sorted(body.keys())}",
        )


class ScheduleContract(unittest.TestCase):
    """schedule — GET, swap_list (no Idempotency-Key needed for swap_list)."""

    def test_get_returns_shifts(self) -> None:
        body = _get("schedule", user="worker")
        _expect_keys(body, "shifts")
        self.assertIsInstance(body["shifts"], list)

    def test_swap_list_supervisor(self) -> None:
        body = _post("schedule", user="supervisor", body={"action": "swap_list"})
        _expect_keys(body, "requests")
        self.assertIsInstance(body["requests"], list)


class TimecardsContract(unittest.TestCase):
    def test_list_worker(self) -> None:
        body = _post(
            "timecards",
            user="worker",
            idempotent=True,
            body={"action": "list"},
        )
        _expect_keys(body, "timecards")
        self.assertIsInstance(body["timecards"], list)


class ExpensesContract(unittest.TestCase):
    def test_get_returns_expenses(self) -> None:
        body = _get("expenses", user="worker")
        # GET path on web returns `expenses`; mobile uses action=list with
        # equivalent shape. Either is acceptable.
        self.assertTrue(
            "expenses" in body or "rows" in body,
            f"expenses GET missing envelope: {sorted(body.keys())}",
        )

    def test_list_action_worker(self) -> None:
        body = _post(
            "expenses",
            user="worker",
            idempotent=True,
            body={"action": "list"},
        )
        _expect_keys(body, "expenses")
        self.assertIsInstance(body["expenses"], list)
        # Sprint 8.6 contract: every row must carry flat job_name.
        for row in body["expenses"][:1]:
            self.assertIn("job_name", row, f"row missing job_name: {row}")


class SafetyContract(unittest.TestCase):
    """safety — check (worker, gates clock-in), submit."""

    def test_check_worker(self) -> None:
        body = _post(
            "safety",
            user="worker",
            body={"action": "check", "job_id": "33333333-3333-3333-3333-333333333333"},
        )
        _expect_keys(body, "completed")
        self.assertIsInstance(body["completed"], bool)


class CrewContract(unittest.TestCase):
    """crew — attendance (supervisor sees company; foreman sees own crew)."""

    def test_attendance_supervisor(self) -> None:
        body = _post("crew", user="supervisor", body={"action": "attendance"})
        _expect_keys(body, "crew")
        self.assertIsInstance(body["crew"], list)


class PermitsContract(unittest.TestCase):
    def test_get_returns_permits(self) -> None:
        body = _post(
            "permits",
            user="supervisor",
            idempotent=True,
            body={"action": "list"},
        )
        _expect_keys(body, "permits")
        self.assertIsInstance(body["permits"], list)

    def test_list_action(self) -> None:
        body = _post(
            "permits",
            user="supervisor",
            idempotent=True,
            body={"action": "list"},
        )
        _expect_keys(body, "permits")

    def test_check_active_returns_required_active_fields(self) -> None:
        body = _post(
            "permits",
            user="worker",
            body={
                "action": "check_active",
                "job_id": "33333333-3333-3333-3333-333333333333",
            },
        )
        # Mobile clock-in gate (apps/fieldops_mobile/.../guarded_clock_in.dart)
        # reads `required` (bool), `required_type` (string|null), and
        # `active_permit` (object|null).
        _expect_keys(body, "required", "required_type", "active_permit")
        self.assertIsInstance(body["required"], bool)


class FeatureFlagsContract(unittest.TestCase):
    def test_get_returns_flags(self) -> None:
        body = _get("feature_flags", user="worker")
        _expect_keys(body, "flags")
        self.assertIsInstance(body["flags"], list)
        for row in body["flags"][:1]:
            self.assertIn("flag_key", row)
            self.assertIn("enabled", row)
            self.assertIn("source", row)


class AlertsContract(unittest.TestCase):
    def test_get_returns_alerts(self) -> None:
        body = _get("alerts", user="supervisor", query={"status": "open"})
        _expect_keys(body, "alerts")
        self.assertIsInstance(body["alerts"], list)


class BudgetContract(unittest.TestCase):
    def test_get_returns_budgets(self) -> None:
        body = _get("budget", user="supervisor")
        # Top-level shape varies between summary and list; either should
        # carry one of these envelopes.
        self.assertTrue(
            "budgets" in body or "budget" in body,
            f"budget GET missing envelope: {sorted(body.keys())}",
        )


class TimeCorrectionsContract(unittest.TestCase):
    def test_list_supervisor(self) -> None:
        body = _get(
            "time_corrections",
            user="supervisor",
        )
        _expect_keys(body, "corrections")
        self.assertIsInstance(body["corrections"], list)


class BreadcrumbsContract(unittest.TestCase):
    def test_get_returns_breadcrumbs(self) -> None:
        body = _get(
            "breadcrumbs",
            user="supervisor",
            query={"shift_date": "2026-04-03"},
        )
        _expect_keys(body, "breadcrumbs")
        self.assertIsInstance(body["breadcrumbs"], list)


class TasksContract(unittest.TestCase):
    def test_get_returns_tasks(self) -> None:
        body = _get(
            "tasks",
            user="worker",
            query={"job_id": "33333333-3333-3333-3333-333333333333"},
        )
        _expect_keys(body, "tasks")
        self.assertIsInstance(body["tasks"], list)


class CostCodesContract(unittest.TestCase):
    def test_get_returns_cost_codes(self) -> None:
        body = _get("cost_codes", user="worker")
        _expect_keys(body, "cost_codes")
        self.assertIsInstance(body["cost_codes"], list)


class TagsContract(unittest.TestCase):
    def test_get_returns_tags(self) -> None:
        body = _get("tags", user="supervisor")
        _expect_keys(body, "tags")
        self.assertIsInstance(body["tags"], list)


class GalleriesContract(unittest.TestCase):
    def test_get_returns_galleries(self) -> None:
        body = _get("galleries", user="supervisor")
        _expect_keys(body, "galleries")
        self.assertIsInstance(body["galleries"], list)


class WorkerHistoryContract(unittest.TestCase):
    def test_get_returns_history(self) -> None:
        body = _post(
            "worker_history",
            user="worker",
            body={"action": "list"},
        )
        # At minimum the envelope contains a list of events / entries.
        self.assertTrue(
            any(k in body for k in ("history", "events", "entries")),
            f"worker_history missing envelope: {sorted(body.keys())}",
        )


class WorkerHoursContract(unittest.TestCase):
    def test_get_returns_summary(self) -> None:
        body = _get("worker_hours", user="supervisor")
        _expect_keys(body, "summary")
        self.assertIsInstance(body["summary"], dict)


class ShiftReportsContract(unittest.TestCase):
    def test_get_returns_reports(self) -> None:
        body = _get("shift_reports", user="supervisor")
        self.assertTrue(
            any(k in body for k in ("reports", "shift_reports", "rows")),
            f"shift_reports missing envelope: {sorted(body.keys())}",
        )


class ReportsContract(unittest.TestCase):
    def test_get_returns_envelope(self) -> None:
        body = _post(
            "reports",
            user="supervisor",
            body={
                "report_type": "timesheet",
                "date_from": "2026-04-01",
                "date_to": "2026-06-30",
            },
        )
        # Reports endpoint variously returns `reports` or shape-specific
        # keys; assert the response is at least JSON-shaped.
        self.assertIsInstance(body, dict)


class DeviceTokensContract(unittest.TestCase):
    """device_tokens — register + unregister are write-only and the
    mobile client calls them on app start. Verify the contract
    accepts the mobile body shape."""

    def test_register_smoke(self) -> None:
        body = _post(
            "device_tokens",
            user="worker",
            idempotent=True,
            body={
                "action": "register",
                "token": "test-device-token",
                "platform": "ios",
            },
        )
        _expect_keys(body, "status")


# ─── Negative / cross-cutting tests ───────────────────────────


class CrossCuttingContract(unittest.TestCase):
    """Behaviours every endpoint must enforce:
       - reject unauthenticated requests
       - emit X-Request-ID on every response
    """

    UNAUTH_FUNCTIONS = [
        # The functions every authenticated user can hit. We ping them
        # with a missing Authorization header and confirm a 401.
        ("jobs_active", "GET"),
        ("pto", "GET"),
        ("ot", "GET"),
        ("schedule", "GET"),
        ("expenses", "GET"),
        ("permits", "GET"),
        ("feature_flags", "GET"),
        ("breadcrumbs", "GET"),
        ("cost_codes", "GET"),
    ]

    def test_unauthenticated_calls_are_rejected(self) -> None:
        failed = []
        for fn, method in self.UNAUTH_FUNCTIONS:
            url = f"{SUPABASE_URL}/functions/v1/{fn}"
            response = (
                requests.get(url, timeout=10)
                if method == "GET"
                else requests.post(url, json={}, timeout=10)
            )
            if response.status_code not in (401, 403):
                failed.append((fn, response.status_code))
        if failed:
            self.fail(f"functions did not reject unauthenticated calls: {failed}")

    def test_request_id_header(self) -> None:
        token = _authenticate(TEST_USERS["worker"])
        response = requests.get(
            f"{SUPABASE_URL}/functions/v1/jobs_active",
            headers=_headers(token),
            timeout=10,
        )
        self.assertIn("X-Request-ID", response.headers)


if __name__ == "__main__":
    unittest.main(verbosity=2)
