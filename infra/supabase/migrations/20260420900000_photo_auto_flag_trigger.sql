-- ========================================================
-- Migration: 20260420900000_photo_auto_flag_trigger
-- Purpose:   FUX-013b — auto-flag photos at insert time when:
--              (a) GPS is >100m outside the job site geofence
--                  (and the job has geofence_enforced=true and site coords),
--              (b) the same user uploaded another photo for the same job
--                  in the last 30 seconds (duplicate / rapid-fire bug).
--            Flags become photo_reviews rows with status='flagged' and
--            auto_flag_reason populated. Supervisors can override via the
--            existing approve/flag UI; absence of a photo_reviews row still
--            implies "unreviewed" (Phase 1 contract preserved).
-- Notes:
--   * Trigger function runs SECURITY DEFINER and grants exec to the
--     authenticated role so the inserting user (worker) writes the review
--     row regardless of the supervisor-only INSERT policy on
--     photo_reviews. This is the standard pattern for system-generated
--     mutable shadow rows.
--   * photo_events is partitioned; AFTER triggers on the partition root
--     fire for inserts on every partition in PG 13+, which we're on.
--   * Idempotent: CREATE OR REPLACE FUNCTION + DROP TRIGGER IF EXISTS.
-- ========================================================

-- Haversine distance in metres between two (lat, lng) points in degrees.
-- earth_distance from cube/earthdistance would also work but pulls in
-- extensions we don't otherwise need. Pure SQL keeps the surface small.
CREATE OR REPLACE FUNCTION public.haversine_m(
  lat1 double precision,
  lng1 double precision,
  lat2 double precision,
  lng2 double precision
) RETURNS double precision
LANGUAGE plpgsql
IMMUTABLE
PARALLEL SAFE
AS $$
DECLARE
  r            CONSTANT double precision := 6371000.0;
  phi1         double precision;
  phi2         double precision;
  delta_phi    double precision;
  delta_lambda double precision;
  a            double precision;
BEGIN
  IF lat1 IS NULL OR lng1 IS NULL OR lat2 IS NULL OR lng2 IS NULL THEN
    RETURN NULL;
  END IF;
  phi1 := radians(lat1);
  phi2 := radians(lat2);
  delta_phi := radians(lat2 - lat1);
  delta_lambda := radians(lng2 - lng1);
  a := sin(delta_phi / 2) ^ 2
       + cos(phi1) * cos(phi2) * sin(delta_lambda / 2) ^ 2;
  RETURN r * 2 * atan2(sqrt(a), sqrt(1 - a));
END;
$$;

COMMENT ON FUNCTION public.haversine_m IS
  'Great-circle distance in metres between two (lat, lng) coordinate pairs in degrees. Returns NULL if any arg is NULL.';

-- Trigger function: decide whether a fresh photo_event should be auto-flagged
-- and, if so, insert the photo_reviews row. Runs after the INSERT commits.
CREATE OR REPLACE FUNCTION public.photo_events_auto_flag()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_job              RECORD;
  v_distance_m       double precision;
  v_reasons          text[] := ARRAY[]::text[];
  v_recent_count     integer;
  v_geofence_buffer  CONSTANT double precision := 100.0;
  v_recent_window    CONSTANT interval := interval '30 seconds';
BEGIN
  -- Pull the job's geofence config once. If the job is gone (race with
  -- ON DELETE CASCADE) bail without flagging — the photo row will go
  -- away on its own.
  SELECT j.site_lat, j.site_lng, j.geofence_radius_m, j.geofence_enforced
    INTO v_job
    FROM public.jobs j
   WHERE j.id = NEW.job_id;
  IF NOT FOUND THEN
    RETURN NEW;
  END IF;

  -- Off-site check — only fires for jobs that ENFORCE geofence and have
  -- valid site coords + GPS on the photo. We allow a 100m buffer on top
  -- of the configured radius so a photo taken from the edge of the
  -- geofence (or with a 10–20m GPS fix wobble) doesn't auto-flag.
  IF COALESCE(v_job.geofence_enforced, true)
     AND v_job.site_lat IS NOT NULL
     AND v_job.site_lng IS NOT NULL
     AND NEW.gps_lat IS NOT NULL
     AND NEW.gps_lng IS NOT NULL
  THEN
    v_distance_m := public.haversine_m(
      v_job.site_lat, v_job.site_lng,
      NEW.gps_lat,    NEW.gps_lng
    );
    IF v_distance_m IS NOT NULL
       AND v_distance_m > (COALESCE(v_job.geofence_radius_m, 100) + v_geofence_buffer)
    THEN
      v_reasons := v_reasons || format(
        'photo_gps_off_site:%sm_from_site',
        round(v_distance_m)::text
      );
    END IF;
  END IF;

  -- Rapid-fire check — same user, same job, within the last 30s.
  -- Reads from photo_events directly; the just-inserted row is excluded
  -- because we filter on id <> NEW.id.
  SELECT count(*) INTO v_recent_count
    FROM public.photo_events pe
   WHERE pe.user_id = NEW.user_id
     AND pe.job_id  = NEW.job_id
     AND pe.id      <> NEW.id
     AND pe.occurred_at >= NEW.occurred_at - v_recent_window
     AND pe.occurred_at <  NEW.occurred_at;
  IF v_recent_count > 0 THEN
    v_reasons := v_reasons || 'rapid_fire_duplicate_candidate';
  END IF;

  -- Insert the review row if we have any reasons. Use ON CONFLICT DO
  -- NOTHING so a concurrent supervisor click doesn't fight us.
  IF cardinality(v_reasons) > 0 THEN
    INSERT INTO public.photo_reviews (
      photo_event_id,
      photo_occurred_at,
      company_id,
      status,
      auto_flag_reason
    ) VALUES (
      NEW.id,
      NEW.occurred_at,
      NEW.company_id,
      'flagged',
      array_to_string(v_reasons, ', ')
    )
    ON CONFLICT (photo_event_id, photo_occurred_at) DO NOTHING;
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.photo_events_auto_flag IS
  'AFTER INSERT trigger on photo_events. Creates a photo_reviews(status=flagged) row when the photo is outside the job geofence or part of a rapid-fire duplicate burst. Supervisors can override via the normal /photos review UI.';

-- Allow the workers/anyone-authenticated role to trigger the function via
-- INSERTs on photo_events. Trigger functions run as their owner under
-- SECURITY DEFINER, so this GRANT is belt-and-suspenders.
REVOKE ALL ON FUNCTION public.photo_events_auto_flag FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.photo_events_auto_flag TO authenticated;

-- Wire onto the partitioned parent. Postgres 13+ propagates the trigger
-- to every existing and future partition.
DROP TRIGGER IF EXISTS trg_photo_events_auto_flag ON public.photo_events;
CREATE TRIGGER trg_photo_events_auto_flag
  AFTER INSERT ON public.photo_events
  FOR EACH ROW EXECUTE FUNCTION public.photo_events_auto_flag();

-- ========================================================
-- Summary (2026-04-21):
--   * haversine_m(lat1,lng1,lat2,lng2) helper.
--   * photo_events_auto_flag() SECURITY DEFINER trigger fn.
--   * trg_photo_events_auto_flag on photo_events (AFTER INSERT, FOR EACH ROW).
--   * Flag if:
--       - geofence_enforced AND site coords + gps known
--         AND distance > geofence_radius_m + 100m buffer
--       - same user inserted another photo for the same job in the
--         previous 30 seconds.
--   * photo_reviews row inserted with status='flagged', auto_flag_reason
--     populated; ON CONFLICT DO NOTHING so a manual review wins.
-- ========================================================
