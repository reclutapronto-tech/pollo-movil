-- Photo review queue (Phase 1) — separate mutable table, preserves event-store immutability.
--
-- Context:
--   photo_events is the immutable evidence record (append-only, partitioned by
--   occurred_at). For a triage workflow — approve / flag / snooze — we need
--   mutable state. We keep that in photo_reviews, keyed by the photo_event
--   composite PK. Each photo has 0 or 1 review row; rows are created lazily by
--   the supervisor clicking approve/flag.
--
-- Phase 1 (this migration):
--   - photo_reviews table with status/flag_reason/reviewer
--   - RLS scoping to company_id, read open to all company users, write to
--     supervisor+
--   - Realtime publication so /photos tabs auto-refresh
--
-- Phase 2 (tracked as FUX-013b):
--   - auto-flag trigger: flag on GPS >100m from job site OR within 30s of
--     previous photo by same user

CREATE TABLE IF NOT EXISTS public.photo_reviews (
  photo_event_id    uuid        NOT NULL,
  photo_occurred_at timestamptz NOT NULL,
  company_id        uuid        NOT NULL REFERENCES public.companies(id) ON DELETE RESTRICT,
  status            text        NOT NULL DEFAULT 'unreviewed'
    CHECK (status IN ('unreviewed', 'approved', 'flagged')),
  flag_reason       text,
  auto_flag_reason  text,  -- reserved for FUX-013b
  reviewed_by       uuid        REFERENCES public.users(id) ON DELETE SET NULL,
  reviewed_at       timestamptz,
  updated_at        timestamptz NOT NULL DEFAULT NOW(),
  PRIMARY KEY (photo_event_id, photo_occurred_at)
);

COMMENT ON TABLE public.photo_reviews IS
  'Mutable review state for photo_events. Composite key mirrors photo_events PK. One row per triaged photo; absence implies "unreviewed" by default.';

CREATE INDEX IF NOT EXISTS idx_photo_reviews_company_status
  ON public.photo_reviews(company_id, status);

CREATE INDEX IF NOT EXISTS idx_photo_reviews_reviewed_at
  ON public.photo_reviews(reviewed_at DESC) WHERE reviewed_at IS NOT NULL;

-- updated_at auto-bump via the shared helper defined in foundation_tables.sql
DROP TRIGGER IF EXISTS set_photo_reviews_updated_at ON public.photo_reviews;
CREATE TRIGGER set_photo_reviews_updated_at
  BEFORE UPDATE ON public.photo_reviews
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- RLS
ALTER TABLE public.photo_reviews ENABLE ROW LEVEL SECURITY;

-- Any authenticated user in the company can SELECT (so the /photos feed
-- shows the same counts to workers who may want to see if their photo was
-- flagged).
CREATE POLICY "Tenant read photo_reviews" ON public.photo_reviews
  FOR SELECT USING (company_id = public.current_company_id());

-- Supervisor+ can INSERT (first review) and UPDATE (change verdict).
CREATE POLICY "Supervisor insert photo_reviews" ON public.photo_reviews
  FOR INSERT WITH CHECK (
    company_id = public.current_company_id()
    AND public.current_user_role() IN ('supervisor', 'admin', 'owner')
  );

CREATE POLICY "Supervisor update photo_reviews" ON public.photo_reviews
  FOR UPDATE USING (
    company_id = public.current_company_id()
    AND public.current_user_role() IN ('supervisor', 'admin', 'owner')
  );

GRANT SELECT, INSERT, UPDATE ON public.photo_reviews TO authenticated;

-- Realtime: broadcast review changes so the /photos UI tabs stay in sync
-- across multiple supervisors reviewing simultaneously.
ALTER PUBLICATION supabase_realtime ADD TABLE public.photo_reviews;
