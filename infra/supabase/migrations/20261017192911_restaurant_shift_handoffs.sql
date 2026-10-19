CREATE TABLE public.restaurant_shift_handoffs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  branch_id uuid NOT NULL REFERENCES public.restaurant_branches(id) ON DELETE CASCADE,
  shift_date date NOT NULL,
  created_by uuid NOT NULL,
  recipient_id uuid,
  client_event_id uuid NOT NULL,
  handoff_note text NOT NULL DEFAULT '' CHECK (length(handoff_note) <= 1000),
  snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
  delivered_at timestamptz NOT NULL DEFAULT now(),
  acknowledged_by uuid,
  acknowledged_at timestamptz,
  FOREIGN KEY (branch_id, created_by)
    REFERENCES public.restaurant_memberships(branch_id, user_id) ON DELETE CASCADE,
  FOREIGN KEY (branch_id, recipient_id)
    REFERENCES public.restaurant_memberships(branch_id, user_id) ON DELETE SET NULL (recipient_id),
  UNIQUE (branch_id, client_event_id),
  UNIQUE (branch_id, id),
  CHECK ((acknowledged_by IS NULL) = (acknowledged_at IS NULL))
);

CREATE INDEX restaurant_shift_handoffs_recent_idx
  ON public.restaurant_shift_handoffs(branch_id, shift_date DESC, delivered_at DESC);
ALTER TABLE public.restaurant_shift_handoffs ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.restaurant_shift_handoffs FROM anon, authenticated;
GRANT SELECT ON public.restaurant_shift_handoffs TO authenticated;
GRANT ALL ON public.restaurant_shift_handoffs TO service_role;
CREATE POLICY restaurant_shift_handoffs_member_read
  ON public.restaurant_shift_handoffs FOR SELECT TO authenticated
  USING (private.restaurant_has_access(branch_id));

ALTER TABLE public.restaurant_notifications
  DROP CONSTRAINT restaurant_notifications_notification_type_check;
ALTER TABLE public.restaurant_notifications
  ADD CONSTRAINT restaurant_notifications_notification_type_check CHECK (
    notification_type IN (
      'task_assigned', 'task_part_assigned', 'incident_assigned', 'incident_reported',
      'shift_handoff_received', 'shift_handoff_acknowledged'
    )
  );
ALTER TABLE public.restaurant_notifications
  DROP CONSTRAINT restaurant_notifications_entity_type_check;
ALTER TABLE public.restaurant_notifications
  ADD CONSTRAINT restaurant_notifications_entity_type_check
  CHECK (entity_type IN ('task', 'incident', 'handoff'));

CREATE OR REPLACE FUNCTION public.notify_restaurant_handoff_delivery()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NEW.recipient_id IS NOT NULL THEN
    INSERT INTO public.restaurant_notifications (
      branch_id, recipient_id, notification_type, title, body, entity_type, entity_id, data
    ) VALUES (
      NEW.branch_id, NEW.recipient_id, 'shift_handoff_received', 'Relevo por recibir',
      pg_catalog.concat('Revisa el relevo del turno del ', NEW.shift_date::text, '.'),
      'handoff', NEW.id, pg_catalog.jsonb_build_object('handoff_id', NEW.id)
    );
  ELSE
    INSERT INTO public.restaurant_notifications (
      branch_id, recipient_id, notification_type, title, body, entity_type, entity_id, data
    )
    SELECT NEW.branch_id, member.user_id, 'shift_handoff_received', 'Relevo por recibir',
      pg_catalog.concat('Revisa el relevo del turno del ', NEW.shift_date::text, '.'),
      'handoff', NEW.id, pg_catalog.jsonb_build_object('handoff_id', NEW.id)
    FROM public.restaurant_memberships AS member
    WHERE member.branch_id = NEW.branch_id
      AND member.is_active
      AND member.access_role IN ('admin', 'supervisor')
      AND member.user_id <> NEW.created_by;
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.notify_restaurant_handoff_acknowledgement()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF OLD.acknowledged_at IS NULL AND NEW.acknowledged_at IS NOT NULL
    AND NEW.created_by IS DISTINCT FROM NEW.acknowledged_by THEN
    INSERT INTO public.restaurant_notifications (
      branch_id, recipient_id, notification_type, title, body, entity_type, entity_id, data
    ) VALUES (
      NEW.branch_id, NEW.created_by, 'shift_handoff_acknowledged', 'Relevo recibido',
      pg_catalog.concat('El relevo del turno del ', NEW.shift_date::text, ' fue recibido.'),
      'handoff', NEW.id,
      pg_catalog.jsonb_build_object('handoff_id', NEW.id, 'acknowledged_by', NEW.acknowledged_by)
    );
  END IF;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.notify_restaurant_handoff_delivery() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.notify_restaurant_handoff_acknowledgement() FROM PUBLIC, anon, authenticated;
CREATE TRIGGER restaurant_handoff_delivery_notification
  AFTER INSERT ON public.restaurant_shift_handoffs
  FOR EACH ROW EXECUTE FUNCTION public.notify_restaurant_handoff_delivery();
CREATE TRIGGER restaurant_handoff_ack_notification
  AFTER UPDATE OF acknowledged_at ON public.restaurant_shift_handoffs
  FOR EACH ROW EXECUTE FUNCTION public.notify_restaurant_handoff_acknowledgement();

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_publication WHERE pubname = 'supabase_realtime')
    AND NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_publication_tables
      WHERE pubname = 'supabase_realtime'
        AND schemaname = 'public'
        AND tablename = 'restaurant_shift_handoffs'
    ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.restaurant_shift_handoffs;
  END IF;
END;
$$;
