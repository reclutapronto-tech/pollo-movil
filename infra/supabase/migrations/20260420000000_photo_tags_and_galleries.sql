-- Sprint 8.5 — Sharing Slice: photo tags, curated galleries, share-link extensions.
--
-- Adds:
--   1. public.photo_tags          — free-form tags on media_assets (CompanyCam-parity)
--   2. public.photo_galleries     — curated photo subsets with public share tokens
--   3. public.photo_gallery_items — M:N between galleries and media_assets
--   4. ALTER job_share_tokens     — password + branding toggle
--
-- RLS uses the existing helpers current_company_id() and current_user_role()
-- (defined in foundation migrations). Public (unauth) access is NOT granted via
-- RLS — public reads go through edge functions using the service-role key.

-- ──────────────────────────────────────────────────────────────
-- 1. photo_tags
-- ──────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.photo_tags (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id      uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  media_asset_id  uuid NOT NULL REFERENCES public.media_assets(id) ON DELETE CASCADE,
  tag             text NOT NULL CHECK (length(trim(tag)) BETWEEN 1 AND 64),
  created_by      uuid NOT NULL REFERENCES public.users(id),
  created_at      timestamptz NOT NULL DEFAULT now()
);

-- One tag value per photo (case-insensitive).
CREATE UNIQUE INDEX IF NOT EXISTS photo_tags_media_asset_tag_uidx
  ON public.photo_tags (media_asset_id, lower(tag));

-- Autocomplete / filter by tenant + tag.
CREATE INDEX IF NOT EXISTS photo_tags_company_tag_idx
  ON public.photo_tags (company_id, lower(tag));

CREATE INDEX IF NOT EXISTS photo_tags_media_asset_idx
  ON public.photo_tags (media_asset_id);

ALTER TABLE public.photo_tags ENABLE ROW LEVEL SECURITY;

-- Any authenticated company member can read / tag / untag. Matches CompanyCam
-- UX: field workers are expected to tag their own photos without admin gate.
CREATE POLICY "Company members can read photo tags"
  ON public.photo_tags
  FOR SELECT
  TO authenticated
  USING (company_id = public.current_company_id());

CREATE POLICY "Company members can insert photo tags"
  ON public.photo_tags
  FOR INSERT
  TO authenticated
  WITH CHECK (
    company_id = public.current_company_id()
    AND created_by = auth.uid()
  );

CREATE POLICY "Company members can delete photo tags"
  ON public.photo_tags
  FOR DELETE
  TO authenticated
  USING (company_id = public.current_company_id());

-- ──────────────────────────────────────────────────────────────
-- 2. photo_galleries
-- ──────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.photo_galleries (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id       uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  job_id           uuid NOT NULL REFERENCES public.jobs(id) ON DELETE CASCADE,
  name             text NOT NULL CHECK (length(trim(name)) BETWEEN 1 AND 160),
  description      text,
  share_token      uuid UNIQUE NOT NULL DEFAULT gen_random_uuid(),
  -- bcrypt hash; null = no password required
  password_hash    text,
  expires_at       timestamptz,
  revoked_at       timestamptz,
  view_count       integer NOT NULL DEFAULT 0,
  last_viewed_at   timestamptz,
  -- When true, public viewer composites tenant logo on each photo.
  brand_watermark  boolean NOT NULL DEFAULT true,
  created_by       uuid NOT NULL REFERENCES public.users(id),
  created_at       timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS photo_galleries_token_idx      ON public.photo_galleries(share_token);
CREATE INDEX IF NOT EXISTS photo_galleries_job_idx        ON public.photo_galleries(job_id);
CREATE INDEX IF NOT EXISTS photo_galleries_company_idx    ON public.photo_galleries(company_id);

ALTER TABLE public.photo_galleries ENABLE ROW LEVEL SECURITY;

-- Read: any company member.
CREATE POLICY "Company members can read photo galleries"
  ON public.photo_galleries
  FOR SELECT
  TO authenticated
  USING (company_id = public.current_company_id());

-- Mutate: supervisors and above. Galleries are a deliverable artifact —
-- not something a field worker should be able to create or revoke.
CREATE POLICY "Supervisors+ manage photo galleries"
  ON public.photo_galleries
  FOR ALL
  TO authenticated
  USING (
    company_id = public.current_company_id()
    AND public.current_user_role() IN ('owner', 'admin', 'supervisor', 'foreman')
  )
  WITH CHECK (
    company_id = public.current_company_id()
    AND public.current_user_role() IN ('owner', 'admin', 'supervisor', 'foreman')
  );

-- ──────────────────────────────────────────────────────────────
-- 3. photo_gallery_items
-- ──────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.photo_gallery_items (
  gallery_id      uuid NOT NULL REFERENCES public.photo_galleries(id) ON DELETE CASCADE,
  media_asset_id  uuid NOT NULL REFERENCES public.media_assets(id) ON DELETE CASCADE,
  position        integer NOT NULL DEFAULT 0,
  added_at        timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (gallery_id, media_asset_id)
);

CREATE INDEX IF NOT EXISTS photo_gallery_items_media_idx
  ON public.photo_gallery_items (media_asset_id);

ALTER TABLE public.photo_gallery_items ENABLE ROW LEVEL SECURITY;

-- Inherit access from parent gallery.
CREATE POLICY "Company members can read gallery items"
  ON public.photo_gallery_items
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.photo_galleries g
      WHERE g.id = photo_gallery_items.gallery_id
        AND g.company_id = public.current_company_id()
    )
  );

CREATE POLICY "Supervisors+ manage gallery items"
  ON public.photo_gallery_items
  FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.photo_galleries g
      WHERE g.id = photo_gallery_items.gallery_id
        AND g.company_id = public.current_company_id()
        AND public.current_user_role() IN ('owner', 'admin', 'supervisor', 'foreman')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.photo_galleries g
      WHERE g.id = photo_gallery_items.gallery_id
        AND g.company_id = public.current_company_id()
        AND public.current_user_role() IN ('owner', 'admin', 'supervisor', 'foreman')
    )
  );

-- ──────────────────────────────────────────────────────────────
-- 4. Extend job_share_tokens with password + watermark
-- ──────────────────────────────────────────────────────────────
ALTER TABLE public.job_share_tokens
  ADD COLUMN IF NOT EXISTS password_hash    text,
  ADD COLUMN IF NOT EXISTS brand_watermark  boolean NOT NULL DEFAULT true;

-- ──────────────────────────────────────────────────────────────
-- 4b. Export kinds — accept photo PDF report templates
-- ──────────────────────────────────────────────────────────────
ALTER TYPE export_kind ADD VALUE IF NOT EXISTS 'photo_insurance_claim';
ALTER TYPE export_kind ADD VALUE IF NOT EXISTS 'photo_daily_log';
ALTER TYPE export_kind ADD VALUE IF NOT EXISTS 'photo_before_after';

-- ──────────────────────────────────────────────────────────────
-- 5. Storage bucket for generated PDF reports
-- ──────────────────────────────────────────────────────────────
-- Private bucket — PDFs are served via short-lived signed URLs from the
-- `reports` edge function. 50 MB cap accommodates photo-heavy packets.
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'reports',
  'reports',
  false,
  52428800,  -- 50MB
  ARRAY['application/pdf']
)
ON CONFLICT (id) DO NOTHING;

-- Read access: company members for their own tenant's reports (path prefix
-- is the company_id). Writes are only ever performed by the service role.
CREATE POLICY "Company members can read their reports"
  ON storage.objects
  FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'reports'
    AND (storage.foldername(name))[1] = public.current_company_id()::text
  );
