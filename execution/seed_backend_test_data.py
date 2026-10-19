#!/usr/bin/env python3
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
SEED_FILE = REPO_ROOT / "infra" / "supabase" / "seed.sql"


def resolve_db_container_name(container_names: list[str]) -> str:
    for name in container_names:
        if name.startswith("supabase_db_"):
            return name
    raise RuntimeError("No running Supabase DB container found.")


def build_seed_command(container_name: str) -> list[str]:
    return [
        "docker",
        "exec",
        "-i",
        container_name,
        "psql",
        "-U",
        "postgres",
        "-d",
        "postgres",
    ]


def log_event(event: str, **payload: object) -> None:
    line = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "event": event,
        **payload,
    }
    print(json.dumps(line), flush=True)


def main() -> int:
    if not SEED_FILE.exists():
        log_event("seed_failed", reason="missing_seed_file", path=str(SEED_FILE))
        return 1

    ps_output = subprocess.run(
        ["docker", "ps", "--format", "{{.Names}}"],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
    )
    if ps_output.returncode != 0:
        log_event("seed_failed", reason="docker_ps_failed", returncode=ps_output.returncode)
        return ps_output.returncode

    container_names = [line.strip() for line in ps_output.stdout.splitlines() if line.strip()]
    try:
        container_name = resolve_db_container_name(container_names)
    except RuntimeError as exc:
        log_event("seed_failed", reason="db_container_not_found", message=str(exc))
        return 1

    command = build_seed_command(container_name)
    log_event("seed_start", command=command, path=str(SEED_FILE))
    with SEED_FILE.open("rb") as seed_handle:
        completed = subprocess.run(command, cwd=REPO_ROOT, stdin=seed_handle)

    log_event("seed_end", command=command, returncode=completed.returncode)
    return completed.returncode


if __name__ == "__main__":
    sys.exit(main())
