-- Harden photo comments write path.
--
-- The product write path is the `photo-comments` edge function because it
-- validates media ownership, parses/validates @mentions, and fans out alerts.
-- Direct authenticated table writes would bypass that logic, so keep direct
-- client access read-only for realtime/select and require service-role writes.

REVOKE INSERT, UPDATE, DELETE ON public.photo_comments FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.photo_comment_mentions FROM authenticated;

DROP POLICY IF EXISTS "Member insert photo_comments" ON public.photo_comments;
DROP POLICY IF EXISTS "Author or supervisor update photo_comments" ON public.photo_comments;
DROP POLICY IF EXISTS "Member insert photo_comment_mentions" ON public.photo_comment_mentions;

GRANT SELECT ON public.photo_comments TO authenticated;
GRANT SELECT ON public.photo_comment_mentions TO authenticated;

COMMENT ON TABLE public.photo_comments IS
  'Threaded comments on a media_asset. Direct authenticated access is read-only; writes go through the photo-comments edge function so @mention validation and alert fan-out cannot be bypassed.';

COMMENT ON TABLE public.photo_comment_mentions IS
  'Validated @mention join rows for photo comments. Direct authenticated access is read-only; rows are written by the photo-comments edge function.';
