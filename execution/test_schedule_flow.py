#!/usr/bin/env python3
import datetime
import json
import sys
import uuid

import requests


SUPABASE_URL = "http://127.0.0.1:54321"
SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0"

SUPERVISOR_ID = "66666666-6666-6666-6666-666666666666"
WORKER_1_ID = "22222222-2222-2222-2222-222222222222"
WORKER_2_ID = "77777777-7777-7777-7777-777777777777"
WORKER_1_JOB_ID = "33333333-3333-3333-3333-333333333333"


def fail(message, payload=None):
    print(f"❌ FAILED: {message}")
    if payload is not None:
        if isinstance(payload, str):
            print(payload)
        else:
            print(json.dumps(payload, indent=2))
    sys.exit(1)


def expect(condition, message, payload=None):
    if not condition:
        fail(message, payload)


def authenticate(email, password="password123"):
    response = requests.post(
        f"{SUPABASE_URL}/auth/v1/token?grant_type=password",
        headers={
            "apikey": SUPABASE_ANON_KEY,
            "Content-Type": "application/json",
        },
        json={"email": email, "password": password},
        timeout=15,
    )
    expect(response.status_code == 200, f"auth failed for {email}", response.text)
    return response.json()["access_token"]


def headers(token, idempotency_key=None):
    payload = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
        "X-Client-Version": "fieldops-web",
    }
    if idempotency_key:
        payload["Idempotency-Key"] = idempotency_key
    return payload


today = datetime.date.today()
week_start = today - datetime.timedelta(days=today.weekday())
shift_date = week_start

print("========================================")
print("🗓️  SCHEDULE FLOW TESTS")
print("========================================\n")

supervisor_token = authenticate("supervisor@test.com")
worker_1_token = authenticate("worker@test.com")
worker_2_token = authenticate("worker2@test.com")
print("✅ SUCCESS: supervisor authenticated\n")

create_payload = {
    "action": "create",
    "worker_id": WORKER_1_ID,
    "job_id": WORKER_1_JOB_ID,
    "shift_date": shift_date.isoformat(),
    "start_time": "07:00",
    "end_time": "15:30",
}

create_response = requests.post(
    f"{SUPABASE_URL}/functions/v1/schedule",
    headers=headers(supervisor_token, str(uuid.uuid4())),
    json=create_payload,
    timeout=15,
)
expect(create_response.status_code == 201, "schedule create failed", create_response.text)
create_body = create_response.json()
shift_id = create_body.get("shift", {}).get("id")
expect(shift_id, "schedule create missing shift id", create_body)
print("✅ SUCCESS: shift draft created")

list_response = requests.get(
    f"{SUPABASE_URL}/functions/v1/schedule?week_start={week_start.isoformat()}",
    headers=headers(supervisor_token),
    timeout=15,
)
expect(list_response.status_code == 200, "schedule list failed", list_response.text)
list_body = list_response.json()
expect(
    any(shift["id"] == shift_id and shift["status"] == "draft" for shift in list_body.get("shifts", [])),
    "draft shift missing from week list",
    list_body,
)
print("✅ SUCCESS: draft shift visible in weekly schedule")

update_response = requests.post(
    f"{SUPABASE_URL}/functions/v1/schedule",
    headers=headers(supervisor_token, str(uuid.uuid4())),
    json={
        "action": "update",
        "shift_id": shift_id,
        "shift_date": (shift_date + datetime.timedelta(days=1)).isoformat(),
        "start_time": "08:00",
        "end_time": "16:00",
        "notes": "Updated by test flow",
    },
    timeout=15,
)
expect(update_response.status_code == 200, "schedule update failed", update_response.text)
update_body = update_response.json()
expect(update_body.get("shift", {}).get("start_time") == "08:00", "updated shift start time missing", update_body)
expect(update_body.get("shift", {}).get("date") == (shift_date + datetime.timedelta(days=1)).isoformat(), "updated shift date missing", update_body)
print("✅ SUCCESS: draft shift edited")

worker_draft_list_response = requests.get(
    f"{SUPABASE_URL}/functions/v1/schedule?week_start={week_start.isoformat()}",
    headers=headers(worker_1_token),
    timeout=15,
)
expect(worker_draft_list_response.status_code == 200, "worker draft schedule list failed", worker_draft_list_response.text)
worker_draft_list = worker_draft_list_response.json()
expect(
    not any(shift["id"] == shift_id for shift in worker_draft_list.get("shifts", [])),
    "worker should not see unpublished draft shift",
    worker_draft_list,
)
print("✅ SUCCESS: draft shift hidden from worker view")

publish_response = requests.post(
    f"{SUPABASE_URL}/functions/v1/schedule",
    headers=headers(supervisor_token, str(uuid.uuid4())),
    json={
        "action": "publish",
        "shift_ids": [shift_id],
    },
    timeout=15,
)
expect(publish_response.status_code == 200, "schedule publish failed", publish_response.text)
publish_body = publish_response.json()
expect(publish_body.get("published_count") == 1, "publish should affect one shift", publish_body)
print("✅ SUCCESS: shift published")

published_list_response = requests.get(
    f"{SUPABASE_URL}/functions/v1/schedule?week_start={week_start.isoformat()}",
    headers=headers(supervisor_token),
    timeout=15,
)
expect(published_list_response.status_code == 200, "published schedule list failed", published_list_response.text)
published_list = published_list_response.json()
expect(
    any(
        shift["id"] == shift_id
        and shift["status"] == "published"
        and shift.get("published_by") == SUPERVISOR_ID
        for shift in published_list.get("shifts", [])
    ),
    "published shift missing expected status",
    published_list,
)
print("✅ SUCCESS: published shift visible in weekly schedule\n")

worker_schedule_response = requests.get(
    f"{SUPABASE_URL}/functions/v1/schedule?week_start={week_start.isoformat()}",
    headers=headers(worker_1_token),
    timeout=15,
)
expect(worker_schedule_response.status_code == 200, "worker published schedule list failed", worker_schedule_response.text)
worker_schedule = worker_schedule_response.json()
expect(
    any(
        shift["id"] == shift_id
        and shift["status"] == "published"
        and shift["worker_id"] == WORKER_1_ID
        and shift.get("published_at")
        for shift in worker_schedule.get("shifts", [])
    ),
    "worker should see own published shift",
    worker_schedule,
)
print("✅ SUCCESS: worker can see own published schedule")

other_worker_schedule_response = requests.get(
    f"{SUPABASE_URL}/functions/v1/schedule?week_start={week_start.isoformat()}",
    headers=headers(worker_2_token),
    timeout=15,
)
expect(other_worker_schedule_response.status_code == 200, "other worker published schedule list failed", other_worker_schedule_response.text)
other_worker_schedule = other_worker_schedule_response.json()
expect(
    not any(shift["id"] == shift_id for shift in other_worker_schedule.get("shifts", [])),
    "other worker should not see another worker's published shift",
    other_worker_schedule,
)
print("✅ SUCCESS: worker view is assignment-scoped\n")

print("========================================")
print("🏁 SCHEDULE TESTS COMPLETE")
print("========================================")
