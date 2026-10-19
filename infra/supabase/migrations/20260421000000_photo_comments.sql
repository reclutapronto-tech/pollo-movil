-- Photo comments + @mentions (Photo Command Center — Slice 1).
--
-- Context:
--   CompanyCam-parity gap: threaded comments on individual photos with
--   @mention notifications. Keyed off media_asset_id (not the photo_events
--   composite PK) so we get a clean ON DELETE CASCADE and mirror photo_tags;
--   media_assets is a normal table with a plain id PK. All company members may
--   comment (unlike photo_reviews, which is supervisor-write).
--
--   Mentions are stored two ways: inline @[Full Name](user_uuid) markup in the
--   body (stable display) AND a normalized photo_comment_mentions join table
--   (indexed "mentions of me" queries + alert fan-out). The photo-comments edge
--   function parses the markup on POST and writes both, then inserts one
--   alert_events row per validated mentioned user.
--
--   Deletion is a soft delete (deleted_at) so removing a parent comment does not
--   orphan its replies; the UI renders deleted parents as a placeholder.

-- ── photo_comments ────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.photo_comments (
  id             uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id     uuid        NOT NULL REFERENCES public.companies(id)    ON DELETE RESTRICT,
  media_asset_id uuid        NOT NULL REFERENCES public.media_assets(id) ON DELETE CASCADE,
  parent_id      uuid        REFERENCES public.photo_comments(id)        ON DELETE CASCADE, -- NULL = top-level
  author_id      uuid        NOT NULL REFERENCES public.users(id)        ON DELETE CASCADE,
  body           text        NOT NULL CHECK (char_length(body) BETWEEN 1 AND 4000),
  deleted_at     timestamptz, -- soft delete so threads don't orphan replies
  created_at     timestamptz NOT NULL DEFAULT NOW(),
  updated_at     timestamptz NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.photo_comments IS
  'Threaded comments on a media_asset. body holds inline @[name](uuid) mention markup; normalized mentions live in photo_comment_mentions. Soft-deleted via deleted_at.';

CREATE INDEX IF NOT EXISTS idx_photo_comments_media_asset
  ON public.photo_comments(media_asset_id, created_at);
CREATE INDEX IF NOT EXISTS idx_photo_comments_company
  ON public.photo_comments(company_id);
CREATE INDEX IF NOT EXISTS idx_photo_comments_parent
  ON public.photo_comments(parent_id) WHERE parent_id IS NOT NULL;

-- ── photo_comment_mentions ───────────────────────────────────
CREATE TABLE IF NOT EXISTS public.photo_comment_mentions (
  comment_id        uuid        NOT NULL REFERENCES public.photo_comments(id) ON DELETE CASCADE,
  mentioned_user_id uuid        NOT NULL REFERENCES public.users(id)          ON DELETE CASCADE,
  company_id        uuid        NOT NULL REFERENCES public.companies(id)      ON DELETE RESTRICT,
  created_at        timestamptz NOT NULL DEFAULT NOW(),
  PRIMARY KEY (comment_id, mentioned_user_id)
);

CREATE INDEX IF NOT EXISTS idx_pcm_user
  ON public.photo_comment_mentions(mentioned_user_id, created_at);

-- ── updated_at trigger (shared helper from foundation_tables.sql) ──
DROP TRIGGER IF EXISTS set_photo_comments_updated_at ON public.photo_comments;
CREATE TRIGGER set_photo_comments_updated_at
  BEFORE UPDATE ON public.photo_comments
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ── RLS ──────────────────────────────────────────────────────
ALTER TABLE public.photo_comments         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.photo_comment_mentions ENABLE ROW LEVEL SECURITY;

-- Any company member can read comments.
CREATE POLICY "Tenant read photo_comments" ON public.photo_comments
  FOR SELECT USING (company_id = public.current_company_id());

-- Any company member can post, but only as themselves.
CREATE POLICY "Member insert photo_comments" ON public.photo_comments
  FOR INSERT WITH CHECK (
    company_id = public.current_company_id()
    AND author_id = auth.uid()
  );

-- Author may edit/soft-delete own; supervisor+ may moderate any.
-- Matches SUPERVISOR_AND_ABOVE_ROLES in functions/_shared/roles.ts.
CREATE POLICY "Author or supervisor update photo_comments" ON public.photo_comments
  FOR UPDATE USING (
    company_id = public.current_company_id()
    AND (
      author_id = auth.uid()
      OR public.current_user_role() IN ('owner', 'admin', 'supervisor', 'foreman')
    )
  );

-- Mentions: explicit policies (grants alone are insufficient once RLS is on).
-- Rows are written server-side via the service role (bypasses RLS); these keep
-- any direct authenticated access tenant-scoped.
CREATE POLICY "Tenant read photo_comment_mentions" ON public.photo_comment_mentions
  FOR SELECT USING (company_id = public.current_company_id());

CREATE POLICY "Member insert photo_comment_mentions" ON public.photo_comment_mentions
  FOR INSERT WITH CHECK (company_id = public.current_company_id());

GRANT SELECT, INSERT, UPDATE ON public.photo_comments         TO authenticated;
GRANT SELECT, INSERT         ON public.photo_comment_mentions TO authenticated;

-- ── Realtime ─────────────────────────────────────────────────
-- Broadcast comment changes so the lightbox comments panel stays in sync.
ALTER PUBLICATION supabase_realtime ADD TABLE public.photo_comments;
