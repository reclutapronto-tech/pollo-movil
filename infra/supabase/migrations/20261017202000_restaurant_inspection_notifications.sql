ALTER TABLE public.restaurant_notifications
  DROP CONSTRAINT restaurant_notifications_notification_type_check;
ALTER TABLE public.restaurant_notifications
  ADD CONSTRAINT restaurant_notifications_notification_type_check CHECK (
    notification_type IN (
      'task_assigned', 'task_part_assigned', 'incident_assigned', 'incident_reported',
      'shift_handoff_received', 'shift_handoff_acknowledged',
      'shift_published', 'shift_updated', 'shift_removed',
      'absence_requested', 'absence_reviewed', 'inspection_attention'
    )
  );
ALTER TABLE public.restaurant_notifications
  DROP CONSTRAINT restaurant_notifications_entity_type_check;
ALTER TABLE public.restaurant_notifications
  ADD CONSTRAINT restaurant_notifications_entity_type_check
  CHECK (entity_type IN ('task', 'incident', 'handoff', 'shift', 'absence', 'inspection'));

CREATE OR REPLACE FUNCTION public.notify_restaurant_inspection_attention()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  template_name text;
BEGIN
  IF NEW.needs_attention_count <= 0 THEN RETURN NEW; END IF;

  SELECT name INTO template_name
  FROM public.restaurant_inspection_templates
  WHERE branch_id = NEW.branch_id AND id = NEW.template_id;

  INSERT INTO public.restaurant_notifications (
    branch_id, recipient_id, notification_type, title, body, entity_type, entity_id, data
  )
  SELECT NEW.branch_id, member.user_id, 'inspection_attention',
    'Inspección requiere seguimiento',
    pg_catalog.concat(template_name, ' · ', NEW.needs_attention_count, ' criterio(s) requieren atención'),
    'inspection', NEW.id,
    pg_catalog.jsonb_build_object(
      'inspection_id', NEW.id,
      'template_id', NEW.template_id,
      'needs_attention_count', NEW.needs_attention_count,
      'inspection_date', NEW.inspection_date
    )
  FROM public.restaurant_memberships AS member
  WHERE member.branch_id = NEW.branch_id
    AND member.is_active
    AND member.access_role IN ('admin', 'supervisor')
    AND member.user_id <> NEW.inspector_id;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.notify_restaurant_inspection_attention() FROM PUBLIC, anon, authenticated;
