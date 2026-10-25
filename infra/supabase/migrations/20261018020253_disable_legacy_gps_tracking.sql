-- Pollo Móvil does not collect continuous GPS trails. Keep historical samples
-- intact, but disable client and supervisor access to the legacy trail table.
DROP POLICY IF EXISTS "Workers insert own breadcrumbs" ON public.gps_breadcrumbs;
DROP POLICY IF EXISTS "Workers see own breadcrumbs" ON public.gps_breadcrumbs;
DROP POLICY IF EXISTS "Supervisors see company breadcrumbs" ON public.gps_breadcrumbs;
REVOKE ALL ON public.gps_breadcrumbs FROM PUBLIC, anon, authenticated;

UPDATE public.feature_flags
SET default_enabled = false,
    description = 'Disabled in Pollo Móvil; location is only checked during configured attendance events.'
WHERE flag_key = 'gps_breadcrumbs';

UPDATE public.company_feature_overrides
SET enabled = false
WHERE flag_key = 'gps_breadcrumbs';

ALTER TABLE public.feature_flags
  ADD CONSTRAINT feature_flags_gps_breadcrumbs_disabled
  CHECK (flag_key <> 'gps_breadcrumbs' OR default_enabled = false);

ALTER TABLE public.company_feature_overrides
  ADD CONSTRAINT company_feature_overrides_gps_breadcrumbs_disabled
  CHECK (flag_key <> 'gps_breadcrumbs' OR enabled = false);
