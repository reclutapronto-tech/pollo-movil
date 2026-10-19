-- ========================================================
-- Migration: 20260404000100_storage_media_policies
-- Purpose:   Allow authenticated company members to read/sign proof media
--            from the private fieldops-media bucket via Storage RLS.
-- ========================================================

CREATE POLICY "Company media read access"
ON storage.objects
FOR SELECT
TO authenticated
USING (
  bucket_id = 'fieldops-media'
  AND (storage.foldername(name))[1] = public.current_company_id()::text
);
