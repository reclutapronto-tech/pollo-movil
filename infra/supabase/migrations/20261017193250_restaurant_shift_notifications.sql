ALTER TABLE public.restaurant_notifications
  DROP CONSTRAINT restaurant_notifications_notification_type_check;
ALTER TABLE public.restaurant_notifications
  ADD CONSTRAINT restaurant_notifications_notification_type_check CHECK (
    notification_type IN (
      'task_assigned', 'task_part_assigned', 'incident_assigned', 'incident_reported',
      'shift_handoff_received', 'shift_handoff_acknowledged',
      'shift_published', 'shift_updated', 'shift_removed'
    )
  );
ALTER TABLE public.restaurant_notifications
  DROP CONSTRAINT restaurant_notifications_entity_type_check;
ALTER TABLE public.restaurant_notifications
  ADD CONSTRAINT restaurant_notifications_entity_type_check
  CHECK (entity_type IN ('task', 'incident', 'handoff', 'shift'));

CREATE OR REPLACE FUNCTION public.notify_restaurant_shift_publication()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  schedule_text text;
  old_schedule_text text;
  schedule_changed boolean := false;
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.status = 'published' THEN
      schedule_text := pg_catalog.concat(
        'Turno ', pg_catalog.to_char(NEW.shift_date, 'DD/MM/YYYY'), ' · ',
        pg_catalog.to_char(NEW.start_time, 'HH24:MI'), '–',
        pg_catalog.to_char(NEW.end_time, 'HH24:MI')
      );
      INSERT INTO public.restaurant_notifications (
        branch_id, recipient_id, notification_type, title, body, entity_type, entity_id, data
      ) VALUES (
        NEW.branch_id, NEW.employee_id, 'shift_published', 'Nuevo turno publicado',
        schedule_text, 'shift', NEW.id,
        pg_catalog.jsonb_build_object('shift_id', NEW.id, 'shift_date', NEW.shift_date)
      );
    END IF;
    RETURN NEW;
  END IF;

  schedule_changed := OLD.employee_id IS DISTINCT FROM NEW.employee_id
    OR OLD.shift_date IS DISTINCT FROM NEW.shift_date
    OR OLD.start_time IS DISTINCT FROM NEW.start_time
    OR OLD.end_time IS DISTINCT FROM NEW.end_time;

  IF OLD.status = 'published'
    AND (NEW.status <> 'published' OR OLD.employee_id IS DISTINCT FROM NEW.employee_id) THEN
    old_schedule_text := pg_catalog.concat(
      'Se retiró el turno del ', pg_catalog.to_char(OLD.shift_date, 'DD/MM/YYYY'), ' · ',
      pg_catalog.to_char(OLD.start_time, 'HH24:MI'), '–',
      pg_catalog.to_char(OLD.end_time, 'HH24:MI')
    );
    INSERT INTO public.restaurant_notifications (
      branch_id, recipient_id, notification_type, title, body, entity_type, entity_id, data
    ) VALUES (
      OLD.branch_id, OLD.employee_id, 'shift_removed', 'Cambio en tu turno',
      old_schedule_text, 'shift', OLD.id,
      pg_catalog.jsonb_build_object('shift_id', OLD.id, 'shift_date', OLD.shift_date)
    );
  END IF;

  IF NEW.status = 'published'
    AND (OLD.status IS DISTINCT FROM NEW.status OR schedule_changed) THEN
    schedule_text := pg_catalog.concat(
      'Turno ', pg_catalog.to_char(NEW.shift_date, 'DD/MM/YYYY'), ' · ',
      pg_catalog.to_char(NEW.start_time, 'HH24:MI'), '–',
      pg_catalog.to_char(NEW.end_time, 'HH24:MI')
    );
    INSERT INTO public.restaurant_notifications (
      branch_id, recipient_id, notification_type, title, body, entity_type, entity_id, data
    ) VALUES (
      NEW.branch_id, NEW.employee_id,
      CASE WHEN OLD.status = 'published' THEN 'shift_updated' ELSE 'shift_published' END,
      CASE WHEN OLD.status = 'published' THEN 'Turno actualizado' ELSE 'Nuevo turno publicado' END,
      schedule_text, 'shift', NEW.id,
      pg_catalog.jsonb_build_object('shift_id', NEW.id, 'shift_date', NEW.shift_date)
    );
  END IF;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.notify_restaurant_shift_publication() FROM PUBLIC, anon, authenticated;
CREATE TRIGGER restaurant_shift_publication_notification
  AFTER INSERT OR UPDATE OF status, employee_id, shift_date, start_time, end_time
  ON public.restaurant_shifts
  FOR EACH ROW EXECUTE FUNCTION public.notify_restaurant_shift_publication();
