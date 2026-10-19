from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from scripts.generate_supabase_sql_snapshot import generate_snapshots, list_migration_files


class GenerateSupabaseSqlSnapshotTests(unittest.TestCase):
    def test_list_migration_files_sorts_by_filename(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            migrations = Path(tmp)
            (migrations / "20260403_b.sql").write_text("-- b\n")
            (migrations / "20260402_a.sql").write_text("-- a\n")

            files = list_migration_files(migrations)

            self.assertEqual([path.name for path in files], ["20260402_a.sql", "20260403_b.sql"])

    def test_generate_snapshots_writes_schema_and_seed_outputs(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            migrations = root / "migrations"
            migrations.mkdir()
            (migrations / "20260402_a.sql").write_text("create table a(id int);\n")
            (migrations / "20260403_b.sql").write_text("create table b(id int);\n")
            seed = root / "seed.sql"
            seed.write_text("insert into a values (1);\n")
            output = root / "generated"

            result = generate_snapshots(migrations, seed, output)

            self.assertEqual(result.migration_count, 2)

            schema = (output / "full_schema.sql").read_text()
            self.assertIn("BEGIN MIGRATION: 20260402_a.sql", schema)
            self.assertIn("create table a(id int);", schema)
            self.assertNotIn("BEGIN SEED", schema)

            schema_with_seed = (output / "full_schema_with_seed.sql").read_text()
            self.assertIn("BEGIN SEED: seed.sql", schema_with_seed)
            self.assertIn("insert into a values (1);", schema_with_seed)


if __name__ == "__main__":
    unittest.main()
