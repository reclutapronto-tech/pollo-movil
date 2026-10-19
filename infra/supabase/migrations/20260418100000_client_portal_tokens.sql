-- Client portal: shareable read-only job links for clients

CREATE TABLE IF NOT EXISTS public.job_share_tokens (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  token         uuid UNIQUE NOT NULL DEFAULT gen_random_uuid(),
  job_id        uuid NOT NULL REFERENCES public.jobs(id) ON DELETE CASCADE,
  company_id    uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  created_by    uuid NOT NULL REFERENCES public.users(id),
  label         text,                        -- optional note (e.g. "Client ABC")
  expires_at    timestamptz,                 -- null = never expires
  revoked_at    timestamptz,                 -- null = active
  view_count    integer NOT NULL DEFAULT 0,
  last_viewed_at timestamptz,
  created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS job_share_tokens_token_idx ON public.job_share_tokens(token);
CREATE INDEX IF NOT EXISTS job_share_tokens_job_id_idx ON public.job_share_tokens(job_id);
CREATE INDEX IF NOT EXISTS job_share_tokens_company_id_idx ON public.job_share_tokens(company_id);

-- Enable RLS
ALTER TABLE public.job_share_tokens ENABLE ROW LEVEL SECURITY;

-- Supervisors and above can manage tokens for their company
CREATE POLICY "Supervisor can manage share tokens"
ON public.job_share_tokens
FOR ALL
TO authenticated
USING (
  company_id = current_company_id()
  AND current_user_role() IN ('owner', 'admin', 'supervisor', 'foreman')
)
WITH CHECK (
  company_id = current_company_id()
  AND current_user_role() IN ('owner', 'admin', 'supervisor', 'foreman')
);
