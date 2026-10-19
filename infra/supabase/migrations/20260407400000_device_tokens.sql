-- Device tokens for push notifications (FCM / APNs).
-- Stores one row per user + device token pair.

CREATE TABLE IF NOT EXISTS public.device_tokens (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  company_id    uuid REFERENCES public.companies(id) ON DELETE CASCADE,
  token         text NOT NULL,
  platform      text NOT NULL CHECK (platform IN ('ios', 'android')),
  created_at    timestamptz NOT NULL DEFAULT now(),
  last_seen_at  timestamptz NOT NULL DEFAULT now(),

  -- One token per user+device combination
  UNIQUE (user_id, token)
);

-- Indexes for common queries
CREATE INDEX IF NOT EXISTS idx_device_tokens_user_id ON public.device_tokens(user_id);
CREATE INDEX IF NOT EXISTS idx_device_tokens_company_id ON public.device_tokens(company_id);

-- RLS
ALTER TABLE public.device_tokens ENABLE ROW LEVEL SECURITY;

-- Workers can manage their own tokens
CREATE POLICY device_tokens_own_select ON public.device_tokens
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY device_tokens_own_insert ON public.device_tokens
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY device_tokens_own_delete ON public.device_tokens
  FOR DELETE USING (auth.uid() = user_id);

CREATE POLICY device_tokens_own_update ON public.device_tokens
  FOR UPDATE USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- Supervisors/admins/owners can read tokens for their company
CREATE POLICY device_tokens_supervisor_read ON public.device_tokens
  FOR SELECT USING (
    company_id IN (
      SELECT (u.raw_user_meta_data->>'company_id')::uuid
      FROM auth.users u
      WHERE u.id = auth.uid()
        AND (u.raw_user_meta_data->>'role') IN ('supervisor', 'admin', 'owner')
    )
  );

-- Comment for documentation
COMMENT ON TABLE public.device_tokens IS 'FCM/APNs device tokens for push notifications. One row per user+device.';
