#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
from dataclasses import dataclass
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
ROOT_ENV = REPO_ROOT / ".env"
WEB_ENV = REPO_ROOT / "apps" / "fieldops_web" / ".env.local"
MOBILE_ENV_DIR = REPO_ROOT / "apps" / "fieldops_mobile" / "env"
MOBILE_ENV = MOBILE_ENV_DIR / "staging.json"


@dataclass(frozen=True)
class SyncResult:
    web_env_path: Path
    mobile_env_path: Path
    hosted: bool
    supabase_url: str


def parse_env_file(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for raw_line in path.read_text().splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()
        if value.startswith(("\"", "'")) and value.endswith(("\"", "'")):
            value = value[1:-1]
        values[key] = value
    return values


def is_hosted_supabase_url(url: str) -> bool:
    lowered = url.lower()
    return bool(url) and not (
        "127.0.0.1" in lowered
        or "localhost" in lowered
        or lowered.startswith("http://10.0.2.2")
        or lowered.startswith("http://192.168.")
        or lowered.startswith("http://10.")
    )


def build_web_env(values: dict[str, str]) -> dict[str, str]:
    web_env = {
        "NEXT_PUBLIC_SUPABASE_URL": values["SUPABASE_URL"],
        "NEXT_PUBLIC_SUPABASE_ANON_KEY": values["SUPABASE_ANON_KEY"],
    }

    optional_pairs = {
        "NEXT_PUBLIC_MAPTILER_KEY": [
            "NEXT_PUBLIC_MAPTILER_KEY",
            "MAPTILER_KEY",
        ],
        "NEXT_PUBLIC_SENTRY_DSN": ["NEXT_PUBLIC_SENTRY_DSN"],
        "NEXT_PUBLIC_POSTHOG_KEY": ["NEXT_PUBLIC_POSTHOG_KEY"],
        "NEXT_PUBLIC_POSTHOG_HOST": ["NEXT_PUBLIC_POSTHOG_HOST"],
        "SENTRY_ORG": ["SENTRY_ORG"],
        "SENTRY_PROJECT": ["SENTRY_PROJECT"],
    }

    for target_key, candidates in optional_pairs.items():
        for candidate in candidates:
          value = values.get(candidate, "").strip()
          if value:
              web_env[target_key] = value
              break

    return web_env


def build_mobile_env(values: dict[str, str]) -> dict[str, str]:
    mobile_env = {
        "SUPABASE_URL": values["SUPABASE_URL"],
        "SUPABASE_ANON_KEY": values["SUPABASE_ANON_KEY"],
    }
    sentry_dsn = values.get("SENTRY_DSN", "").strip()
    if sentry_dsn:
        mobile_env["SENTRY_DSN"] = sentry_dsn
    return mobile_env


def write_web_env(path: Path, values: dict[str, str]) -> None:
    path.write_text("".join(f"{key}={value}\n" for key, value in values.items()))


def write_mobile_env(path: Path, values: dict[str, str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(values, indent=2) + "\n")


def sync_repo_env(repo_root: Path = REPO_ROOT) -> SyncResult:
    root_env = repo_root / ".env"
    if not root_env.exists():
        raise FileNotFoundError(f"Missing root env file: {root_env}")

    values = parse_env_file(root_env)
    missing = [
        key for key in ("SUPABASE_URL", "SUPABASE_ANON_KEY") if not values.get(key)
    ]
    if missing:
        raise ValueError(f"Missing required env keys: {', '.join(missing)}")

    web_env = build_web_env(values)
    mobile_env = build_mobile_env(values)

    web_env_path = repo_root / "apps" / "fieldops_web" / ".env.local"
    mobile_env_path = repo_root / "apps" / "fieldops_mobile" / "env" / "staging.json"
    write_web_env(web_env_path, web_env)
    write_mobile_env(mobile_env_path, mobile_env)

    return SyncResult(
        web_env_path=web_env_path,
        mobile_env_path=mobile_env_path,
        hosted=is_hosted_supabase_url(values["SUPABASE_URL"]),
        supabase_url=values["SUPABASE_URL"],
    )


def main() -> int:
    try:
        result = sync_repo_env()
    except (FileNotFoundError, ValueError) as exc:
        print(f"[sync-runtime-env] {exc}", file=sys.stderr)
        return 1

    env_kind = "hosted" if result.hosted else "local"
    print(f"[sync-runtime-env] synced {env_kind} Supabase config")
    print(f"[sync-runtime-env] web  -> {result.web_env_path}")
    print(f"[sync-runtime-env] mobile -> {result.mobile_env_path}")
    if not result.hosted:
        print(
            "[sync-runtime-env] root .env still points to local Supabase. "
            "Replace SUPABASE_URL/SUPABASE_ANON_KEY with hosted staging values for persistent phone testing."
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
