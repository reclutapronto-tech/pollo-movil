-- Harden export_artifacts write path.
--
-- The reports edge function writes export audit rows with the service role.
-- Authenticated users should be able to read their tenant's artifacts only.

REVOKE INSERT, UPDATE, DELETE ON public.export_artifacts FROM anon, authenticated;
GRANT SELECT ON public.export_artifacts TO authenticated;

COMMENT ON TABLE public.export_artifacts IS
  'Audit trail of generated exports (reports, timesheets, photo packets). Direct authenticated access is read-only; writes are service-role-only through the reports edge function.';
