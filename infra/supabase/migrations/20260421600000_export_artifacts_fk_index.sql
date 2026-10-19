-- Add supporting index for export_artifacts.generated_by FK.
--
-- This FK was introduced after the broad FK-index sweep, so it needs its own
-- index to keep user deletes/updates and export-history joins from scanning.

CREATE INDEX IF NOT EXISTS idx_export_artifacts_generated_by
  ON public.export_artifacts(generated_by);
