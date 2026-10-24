CREATE TABLE public.restaurant_notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  branch_id uuid NOT NULL REFERENCES public.restaurant_branches(id) ON DELETE CASCADE,
  recipient_id uuid NOT NULL,
  notification_type text NOT NULL CHECK (
    notification_type IN ('task_assigned', 'task_part_assigned', 'incident_assigned', 'incident_reported')
  ),
  title text NOT NULL,
  body text NOT NULL,
  entity_type text NOT NULL CHECK (entity_type IN ('task', 'incident')),
  entity_id uuid NOT NULL,
  data jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  read_at timestamptz,
  FOREIGN KEY (branch_id, recipient_id)
    REFERENCES public.restaurant_memberships(branch_id, user_id) ON DELETE CASCADE
);

CREATE INDEX restaurant_notifications_inbox_idx
  ON public.restaurant_notifications(branch_id, recipient_id, created_at DESC);
CREATE INDEX restaurant_notifications_unread_idx
  ON public.restaurant_notifications(branch_id, recipient_id, created_at DESC)
  WHERE read_at IS NULL;

ALTER TABLE public.restaurant_notifications ENABLE ROW LEVEL SECURITY;
CREATE POLICY restaurant_notifications_recipient_read
  ON public.restaurant_notifications FOR SELECT TO authenticated
  USING (
    (SELECT auth.uid()) IS NOT NULL
    AND recipient_id = (SELECT auth.uid())
    AND private.restaurant_has_access(branch_id)
  );
CREATE POLICY restaurant_notifications_recipient_mark_read
  ON public.restaurant_notifications FOR UPDATE TO authenticated
  USING (
    (SELECT auth.uid()) IS NOT NULL
    AND recipient_id = (SELECT auth.uid())
    AND private.restaurant_has_access(branch_id)
  )
  WITH CHECK (
    (SELECT auth.uid()) IS NOT NULL
    AND recipient_id = (SELECT auth.uid())
    AND private.restaurant_has_access(branch_id)
  );

REVOKE ALL ON public.restaurant_notifications FROM anon;
REVOKE ALL ON public.restaurant_notifications FROM authenticated;
GRANT SELECT, UPDATE (read_at) ON public.restaurant_notifications TO authenticated;
GRANT ALL ON public.restaurant_notifications TO service_role;

CREATE OR REPLACE FUNCTION public.notify_restaurant_task_assignment()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  notify_assignment boolean := false;
BEGIN
  IF TG_OP = 'INSERT' THEN
    notify_assignment := NEW.assigned_to IS NOT NULL;
  ELSE
    notify_assignment := NEW.assigned_to IS NOT NULL
      AND NEW.assigned_to IS DISTINCT FROM OLD.assigned_to;
  END IF;

  IF notify_assignment THEN
    INSERT INTO public.restaurant_notifications (
      branch_id, recipient_id, notification_type, title, body, entity_type, entity_id, data
    ) VALUES (
      NEW.branch_id, NEW.assigned_to, 'task_assigned', 'Actividad asignada',
      NEW.name, 'task', NEW.id,
      pg_catalog.jsonb_build_object('task_id', NEW.id, 'scheduled_for', NEW.scheduled_for)
    );
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.notify_restaurant_task_part_assignment()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  notify_assignment boolean := false;
  task_name text;
  zone_name text;
BEGIN
  IF TG_OP = 'INSERT' THEN
    notify_assignment := NEW.assigned_to IS NOT NULL;
  ELSE
    notify_assignment := NEW.assigned_to IS NOT NULL
      AND NEW.assigned_to IS DISTINCT FROM OLD.assigned_to;
  END IF;

  IF notify_assignment THEN
    SELECT task.name, zone.name INTO task_name, zone_name
    FROM public.restaurant_tasks AS task
    JOIN public.restaurant_activity_zones AS zone
      ON zone.branch_id = NEW.branch_id AND zone.id = NEW.zone_id
    WHERE task.branch_id = NEW.branch_id AND task.id = NEW.task_id;

    INSERT INTO public.restaurant_notifications (
      branch_id, recipient_id, notification_type, title, body, entity_type, entity_id, data
    ) VALUES (
      NEW.branch_id, NEW.assigned_to, 'task_part_assigned', 'Parte de actividad asignada',
      pg_catalog.concat_ws(' · ', task_name, zone_name), 'task', NEW.task_id,
      pg_catalog.jsonb_build_object('task_id', NEW.task_id, 'part_id', NEW.id, 'zone_id', NEW.zone_id)
    );
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.notify_restaurant_incident_assignment()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  notify_assignment boolean := false;
BEGIN
  IF TG_OP = 'INSERT' THEN
    notify_assignment := NEW.assigned_to IS NOT NULL;
  ELSE
    notify_assignment := NEW.assigned_to IS NOT NULL
      AND NEW.assigned_to IS DISTINCT FROM OLD.assigned_to;
  END IF;

  IF notify_assignment THEN
    INSERT INTO public.restaurant_notifications (
      branch_id, recipient_id, notification_type, title, body, entity_type, entity_id, data
    ) VALUES (
      NEW.branch_id, NEW.assigned_to, 'incident_assigned', 'Incidencia asignada',
      pg_catalog.left(NEW.description, 240), 'incident', NEW.id,
      pg_catalog.jsonb_build_object('incident_id', NEW.id, 'urgency', NEW.urgency)
    );
  END IF;

  IF TG_OP = 'INSERT' THEN
    INSERT INTO public.restaurant_notifications (
      branch_id, recipient_id, notification_type, title, body, entity_type, entity_id, data
    )
    SELECT NEW.branch_id, member.user_id, 'incident_reported', 'Nueva incidencia',
      pg_catalog.left(NEW.description, 240), 'incident', NEW.id,
      pg_catalog.jsonb_build_object('incident_id', NEW.id, 'urgency', NEW.urgency)
    FROM public.restaurant_memberships AS member
    WHERE member.branch_id = NEW.branch_id
      AND member.is_active
      AND member.access_role IN ('admin', 'supervisor')
      AND member.user_id <> NEW.reported_by
      AND member.user_id IS DISTINCT FROM NEW.assigned_to;
  END IF;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.notify_restaurant_task_assignment() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.notify_restaurant_task_part_assignment() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.notify_restaurant_incident_assignment() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER restaurant_task_assignment_notification
  AFTER INSERT OR UPDATE OF assigned_to ON public.restaurant_tasks
  FOR EACH ROW EXECUTE FUNCTION public.notify_restaurant_task_assignment();
CREATE TRIGGER restaurant_task_part_assignment_notification
  AFTER INSERT OR UPDATE OF assigned_to ON public.restaurant_task_parts
  FOR EACH ROW EXECUTE FUNCTION public.notify_restaurant_task_part_assignment();
CREATE TRIGGER restaurant_incident_assignment_notification
  AFTER INSERT OR UPDATE OF assigned_to ON public.restaurant_incidents
  FOR EACH ROW EXECUTE FUNCTION public.notify_restaurant_incident_assignment();

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_publication WHERE pubname = 'supabase_realtime')
    AND NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_publication_tables
      WHERE pubname = 'supabase_realtime'
        AND schemaname = 'public'
        AND tablename = 'restaurant_notifications'
    ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.restaurant_notifications;
  END IF;
END;
$$;
