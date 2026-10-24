ALTER TABLE public.restaurant_notifications
  DROP CONSTRAINT restaurant_notifications_notification_type_check;
ALTER TABLE public.restaurant_notifications
  ADD CONSTRAINT restaurant_notifications_notification_type_check CHECK (
    notification_type IN (
      'task_assigned', 'task_part_assigned', 'incident_assigned', 'incident_reported',
      'shift_handoff_received', 'shift_handoff_acknowledged',
      'shift_published', 'shift_updated', 'shift_removed',
      'absence_requested', 'absence_reviewed'
    )
  );
ALTER TABLE public.restaurant_notifications
  DROP CONSTRAINT restaurant_notifications_entity_type_check;
ALTER TABLE public.restaurant_notifications
  ADD CONSTRAINT restaurant_notifications_entity_type_check
  CHECK (entity_type IN ('task', 'incident', 'handoff', 'shift', 'absence'));

ALTER TABLE public.restaurant_absences
  ADD COLUMN client_event_id uuid;
ALTER TABLE public.restaurant_absences
  ADD CONSTRAINT restaurant_absences_branch_client_event_id_key
  UNIQUE (branch_id, client_event_id);

CREATE POLICY restaurant_absences_employee_read
  ON public.restaurant_absences FOR SELECT TO authenticated
  USING (
    private.restaurant_has_access(branch_id)
    AND (employee_id = (SELECT auth.uid()) OR private.restaurant_can_manage(branch_id))
  );

CREATE OR REPLACE FUNCTION public.notify_restaurant_absence_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF TG_OP = 'INSERT' AND NEW.status = 'pending' THEN
    INSERT INTO public.restaurant_notifications (
      branch_id, recipient_id, notification_type, title, body, entity_type, entity_id, data
    )
    SELECT NEW.branch_id, member.user_id, 'absence_requested', 'Solicitud de ausencia',
      pg_catalog.concat('Solicitud del ', pg_catalog.to_char(NEW.start_date, 'DD/MM/YYYY'),
        ' al ', pg_catalog.to_char(NEW.end_date, 'DD/MM/YYYY')),
      'absence', NEW.id,
      pg_catalog.jsonb_build_object('absence_id', NEW.id, 'employee_id', NEW.employee_id)
    FROM public.restaurant_memberships AS member
    WHERE member.branch_id = NEW.branch_id
      AND member.is_active
      AND member.access_role IN ('admin', 'supervisor')
      AND member.user_id <> NEW.employee_id
      AND member.user_id <> NEW.created_by;
  ELSIF TG_OP = 'UPDATE' AND OLD.status = 'pending'
    AND NEW.status IN ('approved', 'denied') THEN
    INSERT INTO public.restaurant_notifications (
      branch_id, recipient_id, notification_type, title, body, entity_type, entity_id, data
    ) VALUES (
      NEW.branch_id, NEW.employee_id, 'absence_reviewed',
      CASE WHEN NEW.status = 'approved' THEN 'Ausencia aprobada' ELSE 'Solicitud de ausencia no aprobada' END,
      pg_catalog.concat('Solicitud del ', pg_catalog.to_char(NEW.start_date, 'DD/MM/YYYY'),
        ' al ', pg_catalog.to_char(NEW.end_date, 'DD/MM/YYYY')),
      'absence', NEW.id,
      pg_catalog.jsonb_build_object('absence_id', NEW.id, 'status', NEW.status)
    );
  END IF;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.notify_restaurant_absence_change() FROM PUBLIC, anon, authenticated;
CREATE TRIGGER restaurant_absence_insert_notification
  AFTER INSERT ON public.restaurant_absences
  FOR EACH ROW EXECUTE FUNCTION public.notify_restaurant_absence_change();
CREATE TRIGGER restaurant_absence_review_notification
  AFTER UPDATE OF status ON public.restaurant_absences
  FOR EACH ROW EXECUTE FUNCTION public.notify_restaurant_absence_change();

DO $$
DECLARE
  table_name text;
BEGIN
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_publication WHERE pubname = 'supabase_realtime') THEN
    FOREACH table_name IN ARRAY ARRAY[
      'restaurant_absences', 'restaurant_shifts', 'restaurant_waste_bins', 'restaurant_memberships'
    ] LOOP
      IF NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_publication_tables
        WHERE pubname = 'supabase_realtime'
          AND schemaname = 'public'
          AND tablename = table_name
      ) THEN
        EXECUTE pg_catalog.format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', table_name);
      END IF;
    END LOOP;
  END IF;
END;
$$;
