# Supabase SQL Snapshots

These files are generated from the migration chain in [../migrations](/Users/seancheick/FieldsOps_ai/infra/supabase/migrations).

Files:

- [full_schema.sql](/Users/seancheick/FieldsOps_ai/infra/supabase/generated/full_schema.sql)
  - Hosted bootstrap snapshot
  - Schema, policies, functions, storage config, indexes, views
  - No demo seed data

- [full_schema_with_seed.sql](/Users/seancheick/FieldsOps_ai/infra/supabase/generated/full_schema_with_seed.sql)
  - Same schema snapshot plus [../seed.sql](/Users/seancheick/FieldsOps_ai/infra/supabase/seed.sql)
  - Intended for local/demo resets only

Regenerate:

```bash
cd /Users/seancheick/FieldsOps_ai
python3 scripts/generate_supabase_sql_snapshot.py
```

Recommended usage:

- Hosted staging / production: use `full_schema.sql`
- Local demo / testing: use `full_schema_with_seed.sql`

Normal source of truth is still the migration chain. These files are convenience snapshots.
