-- Durable, retryable delivery for mobile push notifications.
-- The in-app restaurant_notifications inbox remains the source of truth;
-- this table only tracks best-effort FCM delivery.

CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

CREATE TABLE public.restaurant_push_outbox (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  notification_id uuid NOT NULL UNIQUE
    REFERENCES public.restaurant_notifications(id) ON DELETE CASCADE,
  attempts integer NOT NULL DEFAULT 0 CHECK (attempts >= 0),
  available_at timestamptz NOT NULL DEFAULT now(),
  lease_until timestamptz,
  sent_at timestamptz,
  failed_at timestamptz,
  last_error text,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (sent_at IS NULL OR failed_at IS NULL)
);

CREATE INDEX restaurant_push_outbox_pending_idx
  ON public.restaurant_push_outbox(available_at, created_at)
  WHERE sent_at IS NULL AND failed_at IS NULL;

ALTER TABLE public.restaurant_push_outbox ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.restaurant_push_outbox FROM anon, authenticated;
GRANT ALL ON public.restaurant_push_outbox TO service_role;

CREATE OR REPLACE FUNCTION private.dispatch_restaurant_push()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  supabase_url text;
  cron_secret text;
BEGIN
  SELECT decrypted_secret INTO supabase_url
  FROM vault.decrypted_secrets
  WHERE name = 'SUPABASE_URL';

  SELECT decrypted_secret INTO cron_secret
  FROM vault.decrypted_secrets
  WHERE name = 'CRON_SECRET';

  IF supabase_url IS NOT NULL AND cron_secret IS NOT NULL THEN
    PERFORM net.http_post(
      url := pg_catalog.rtrim(supabase_url, '/') || '/functions/v1/restaurant_push',
      headers := pg_catalog.jsonb_build_object(
        'Content-Type', 'application/json',
        'x-cron-secret', cron_secret
      ),
      body := pg_catalog.jsonb_build_object('notification_id', NEW.notification_id)
    );
  END IF;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'restaurant push dispatch request could not be queued; the inbox notification remains available';
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION private.dispatch_restaurant_push() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER restaurant_push_outbox_dispatch
  AFTER INSERT ON public.restaurant_push_outbox
  FOR EACH ROW EXECUTE FUNCTION private.dispatch_restaurant_push();

CREATE OR REPLACE FUNCTION private.enqueue_restaurant_push()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  INSERT INTO public.restaurant_push_outbox(notification_id)
  VALUES (NEW.id)
  ON CONFLICT (notification_id) DO NOTHING;
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'restaurant push outbox could not be created; the inbox notification remains available';
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION private.enqueue_restaurant_push() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER restaurant_notification_enqueue_push
  AFTER INSERT ON public.restaurant_notifications
  FOR EACH ROW EXECUTE FUNCTION private.enqueue_restaurant_push();

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'restaurant-push-retry') THEN
    PERFORM cron.unschedule('restaurant-push-retry');
  END IF;
END
$$;

SELECT cron.schedule(
  'restaurant-push-retry',
  '* * * * *',
  $cron$
    SELECT net.http_post(
      url := pg_catalog.rtrim(
        (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'SUPABASE_URL'),
        '/'
      ) || '/functions/v1/restaurant_push',
      headers := pg_catalog.jsonb_build_object(
        'Content-Type', 'application/json',
        'x-cron-secret',
        (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'CRON_SECRET')
      ),
      body := '{}'::jsonb
    )
    WHERE (SELECT count(*) FROM vault.decrypted_secrets
           WHERE name IN ('SUPABASE_URL', 'CRON_SECRET')) = 2
  $cron$
);
