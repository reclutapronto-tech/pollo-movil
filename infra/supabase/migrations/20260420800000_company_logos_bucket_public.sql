-- Make company-logos bucket public so getPublicUrl() actually resolves.
--
-- Bug: 20260406000000_admin_system.sql created the bucket with public=false.
-- The company_logo edge function then calls supabaseAdmin.storage.getPublicUrl()
-- and stores the returned URL on companies.logo_url. Sidebar + LogoUpload
-- render that URL in <img src>. But getPublicUrl() on a private bucket returns
-- a URL that 404/403s when fetched unauthenticated (which <img> tags always are)
-- — the user sees a broken image placeholder right after uploading.
--
-- Fix: flip the bucket to public. Company logos are public information
-- anyway (displayed on client-facing portals, PDF reports, shared galleries).
-- Paths are `{companyId}/logo.png` where companyId is a UUID, so the bucket
-- being public doesn't enumerate companies — you have to already know the ID.
--
-- The existing storage RLS policies remain in place; they still gate signed-URL
-- reads, inserts, and deletes to the owning company's authenticated users.
-- Public bucket behavior only enables CDN-style reads of the raw object by URL.

UPDATE storage.buckets
SET public = true,
    updated_at = now()
WHERE id = 'company-logos';
