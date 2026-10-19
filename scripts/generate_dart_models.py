#!/usr/bin/env python3
"""
Generate Flutter/Dart model classes from the Supabase Postgres schema.

Connects to the local Supabase instance via docker exec and queries
information_schema.columns for all public tables.

Usage:
    python3 scripts/generate_dart_models.py

Output:
    apps/fieldops_mobile/lib/core/models/generated/<table_name>.dart
    apps/fieldops_mobile/lib/core/models/generated/generated.dart  (barrel)
"""

import os
import re
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
OUTPUT_DIR = REPO_ROOT / "apps" / "fieldops_mobile" / "lib" / "core" / "models" / "generated"
HEADER = "// GENERATED — do not edit manually. Run: python3 scripts/generate_dart_models.py\n"

# Postgres → Dart type mapping
TYPE_MAP = {
    "uuid": "String",
    "text": "String",
    "character varying": "String",
    "varchar": "String",
    "boolean": "bool",
    "integer": "int",
    "bigint": "int",
    "smallint": "int",
    "numeric": "double",
    "double precision": "double",
    "real": "double",
    "timestamp with time zone": "DateTime",
    "timestamp without time zone": "DateTime",
    "timestamptz": "DateTime",
    "date": "DateTime",
    "jsonb": "Map<String, dynamic>",
    "json": "Map<String, dynamic>",
    "ARRAY": "List<dynamic>",
}


def run_sql(sql: str) -> str:
    """Execute SQL against local Supabase Postgres."""
    result = subprocess.run(
        [
            "docker", "exec", "-i", "supabase_db_infra",
            "psql", "-U", "postgres", "-d", "postgres", "-t", "-A", "-c", sql,
        ],
        capture_output=True,
        text=True,
        timeout=15,
    )
    if result.returncode != 0:
        print(f"SQL error: {result.stderr.strip()}", file=sys.stderr)
        sys.exit(1)
    return result.stdout.strip()


def get_tables() -> list[str]:
    """Get all public-schema base tables."""
    rows = run_sql(
        "SELECT table_name FROM information_schema.tables "
        "WHERE table_schema = 'public' AND table_type = 'BASE TABLE' "
        "ORDER BY table_name;"
    )
    return [r for r in rows.splitlines() if r]


def get_columns(table: str) -> list[dict]:
    """Get column info for a table."""
    rows = run_sql(
        f"SELECT column_name, data_type, is_nullable, column_default "
        f"FROM information_schema.columns "
        f"WHERE table_schema = 'public' AND table_name = '{table}' "
        f"ORDER BY ordinal_position;"
    )
    columns = []
    for row in rows.splitlines():
        if not row:
            continue
        parts = row.split("|")
        if len(parts) < 3:
            continue
        columns.append({
            "name": parts[0],
            "data_type": parts[1],
            "nullable": parts[2] == "YES",
            "has_default": bool(parts[3]) if len(parts) > 3 else False,
        })
    return columns


def to_camel_case(snake: str) -> str:
    """Convert snake_case to camelCase."""
    parts = snake.split("_")
    return parts[0] + "".join(p.capitalize() for p in parts[1:])


def to_pascal_case(snake: str) -> str:
    """Convert snake_case to PascalCase."""
    return "".join(p.capitalize() for p in snake.split("_"))


def dart_type(pg_type: str, nullable: bool) -> str:
    """Map Postgres type to Dart type."""
    dt = TYPE_MAP.get(pg_type, "dynamic")
    if nullable:
        return f"{dt}?"
    return dt


def from_json_expr(col: dict) -> str:
    """Generate fromJson expression for a column."""
    name = col["name"]
    camel = to_camel_case(name)
    pg_type = col["data_type"]
    nullable = col["nullable"]
    dt = TYPE_MAP.get(pg_type, "dynamic")

    if dt == "DateTime":
        if nullable:
            return f"{camel}: json['{name}'] != null ? DateTime.parse(json['{name}'] as String) : null"
        return f"{camel}: DateTime.parse(json['{name}'] as String)"

    if dt == "int":
        if nullable:
            return f"{camel}: (json['{name}'] as num?)?.toInt()"
        return f"{camel}: (json['{name}'] as num).toInt()"

    if dt == "double":
        if nullable:
            return f"{camel}: (json['{name}'] as num?)?.toDouble()"
        return f"{camel}: (json['{name}'] as num).toDouble()"

    if dt == "Map<String, dynamic>":
        if nullable:
            return f"{camel}: json['{name}'] != null ? Map<String, dynamic>.from(json['{name}'] as Map) : null"
        return f"{camel}: Map<String, dynamic>.from(json['{name}'] as Map)"

    if dt == "List<dynamic>":
        if nullable:
            return f"{camel}: json['{name}'] != null ? List<dynamic>.from(json['{name}'] as List) : null"
        return f"{camel}: List<dynamic>.from(json['{name}'] as List)"

    if nullable:
        return f"{camel}: json['{name}'] as {dt}?"
    return f"{camel}: json['{name}'] as {dt}"


def to_json_expr(col: dict) -> str:
    """Generate toJson expression for a column."""
    name = col["name"]
    camel = to_camel_case(name)
    pg_type = col["data_type"]
    dt = TYPE_MAP.get(pg_type, "dynamic")

    if dt == "DateTime":
        if col["nullable"]:
            return f"'{name}': {camel}?.toIso8601String()"
        return f"'{name}': {camel}.toIso8601String()"

    return f"'{name}': {camel}"


def generate_model(table: str, columns: list[dict]) -> str:
    """Generate a Dart model class for a table."""
    class_name = to_pascal_case(table)
    lines = [HEADER, f"class {class_name} {{"]

    # Fields
    for col in columns:
        camel = to_camel_case(col["name"])
        dt = dart_type(col["data_type"], col["nullable"])
        lines.append(f"  final {dt} {camel};")

    lines.append("")

    # Constructor
    lines.append(f"  const {class_name}({{")
    for col in columns:
        camel = to_camel_case(col["name"])
        if col["nullable"]:
            lines.append(f"    this.{camel},")
        else:
            lines.append(f"    required this.{camel},")
    lines.append("  });")
    lines.append("")

    # fromJson
    lines.append(f"  factory {class_name}.fromJson(Map<String, dynamic> json) {{")
    lines.append(f"    return {class_name}(")
    for col in columns:
        lines.append(f"      {from_json_expr(col)},")
    lines.append("    );")
    lines.append("  }")
    lines.append("")

    # toJson
    lines.append("  Map<String, dynamic> toJson() {")
    lines.append("    return {")
    for col in columns:
        lines.append(f"      {to_json_expr(col)},")
    lines.append("    };")
    lines.append("  }")

    lines.append("}")
    lines.append("")
    return "\n".join(lines)


def main() -> int:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    tables = get_tables()
    if not tables:
        print("No tables found in public schema.", file=sys.stderr)
        return 1

    print(f"Found {len(tables)} tables in public schema")
    generated_files: list[str] = []

    for table in tables:
        columns = get_columns(table)
        if not columns:
            print(f"  Skipping {table} (no columns)")
            continue

        model_code = generate_model(table, columns)
        filename = f"{table}.dart"
        filepath = OUTPUT_DIR / filename
        filepath.write_text(model_code)
        generated_files.append(filename)
        print(f"  ✓ {table} → {filename} ({len(columns)} columns)")

    # Barrel file
    barrel = [HEADER]
    for f in sorted(generated_files):
        barrel.append(f"export '{f}';")
    barrel.append("")
    (OUTPUT_DIR / "generated.dart").write_text("\n".join(barrel))

    print(f"\nGenerated {len(generated_files)} models → {OUTPUT_DIR.relative_to(REPO_ROOT)}")
    print(f"Barrel file → generated.dart")
    return 0


if __name__ == "__main__":
    sys.exit(main())
