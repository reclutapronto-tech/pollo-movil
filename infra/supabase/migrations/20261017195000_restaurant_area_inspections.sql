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

CREATE TABLE public.restaurant_inspection_templates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  branch_id uuid NOT NULL REFERENCES public.restaurant_branches(id) ON DELETE CASCADE,
  area_id uuid,
  name text NOT NULL CHECK (length(trim(name)) BETWEEN 2 AND 120),
  inspection_interval_minutes integer CHECK (
    inspection_interval_minutes IS NULL OR inspection_interval_minutes BETWEEN 1 AND 10080
  ),
  last_inspected_at timestamptz,
  is_active boolean NOT NULL DEFAULT true,
  created_by uuid REFERENCES public.users(id) ON DELETE SET NULL,
  updated_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (branch_id, area_id)
    REFERENCES public.restaurant_areas(branch_id, id) ON DELETE SET NULL (area_id),
  UNIQUE (branch_id, id)
);

CREATE TABLE public.restaurant_inspection_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  branch_id uuid NOT NULL,
  template_id uuid NOT NULL,
  label text NOT NULL CHECK (length(trim(label)) BETWEEN 2 AND 180),
  sort_order integer NOT NULL DEFAULT 0 CHECK (sort_order >= 0),
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (branch_id, template_id)
    REFERENCES public.restaurant_inspection_templates(branch_id, id) ON DELETE CASCADE,
  UNIQUE (branch_id, id)
);

CREATE TABLE public.restaurant_inspections (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  branch_id uuid NOT NULL,
  template_id uuid NOT NULL,
  inspector_id uuid NOT NULL,
  client_event_id uuid NOT NULL,
  inspection_date date NOT NULL,
  inspected_at timestamptz NOT NULL DEFAULT now(),
  note text NOT NULL DEFAULT '' CHECK (length(note) <= 1000),
  needs_attention_count integer NOT NULL DEFAULT 0 CHECK (needs_attention_count >= 0),
  FOREIGN KEY (branch_id, template_id)
    REFERENCES public.restaurant_inspection_templates(branch_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (branch_id, inspector_id)
    REFERENCES public.restaurant_memberships(branch_id, user_id) ON DELETE RESTRICT,
  UNIQUE (branch_id, client_event_id),
  UNIQUE (branch_id, id)
);

CREATE TABLE public.restaurant_inspection_results (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  branch_id uuid NOT NULL,
  inspection_id uuid NOT NULL,
  item_id uuid NOT NULL,
  item_label text NOT NULL,
  result_state text NOT NULL CHECK (result_state IN ('ok', 'needs_attention', 'not_applicable')),
  note text NOT NULL DEFAULT '' CHECK (length(note) <= 500),
  FOREIGN KEY (branch_id, inspection_id)
    REFERENCES public.restaurant_inspections(branch_id, id) ON DELETE CASCADE,
  FOREIGN KEY (branch_id, item_id)
    REFERENCES public.restaurant_inspection_items(branch_id, id) ON DELETE RESTRICT,
  UNIQUE (inspection_id, item_id)
);

CREATE INDEX restaurant_inspection_templates_branch_idx
  ON public.restaurant_inspection_templates(branch_id, is_active, name);
CREATE INDEX restaurant_inspection_items_template_idx
  ON public.restaurant_inspection_items(branch_id, template_id, is_active, sort_order);
CREATE INDEX restaurant_inspections_recent_idx
  ON public.restaurant_inspections(branch_id, inspected_at DESC);
CREATE INDEX restaurant_inspections_template_idx
  ON public.restaurant_inspections(branch_id, template_id, inspected_at DESC);
CREATE INDEX restaurant_inspection_results_inspection_idx
  ON public.restaurant_inspection_results(branch_id, inspection_id, result_state);

ALTER TABLE public.restaurant_inspection_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.restaurant_inspection_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.restaurant_inspections ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.restaurant_inspection_results ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.restaurant_inspection_templates FROM anon, authenticated;
REVOKE ALL ON public.restaurant_inspection_items FROM anon, authenticated;
REVOKE ALL ON public.restaurant_inspections FROM anon, authenticated;
REVOKE ALL ON public.restaurant_inspection_results FROM anon, authenticated;
GRANT SELECT ON public.restaurant_inspection_templates TO authenticated;
GRANT SELECT ON public.restaurant_inspection_items TO authenticated;
GRANT SELECT ON public.restaurant_inspections TO authenticated;
GRANT SELECT ON public.restaurant_inspection_results TO authenticated;
GRANT ALL ON public.restaurant_inspection_templates TO service_role;
GRANT ALL ON public.restaurant_inspection_items TO service_role;
GRANT ALL ON public.restaurant_inspections TO service_role;
GRANT ALL ON public.restaurant_inspection_results TO service_role;

CREATE POLICY restaurant_inspection_templates_member_read
  ON public.restaurant_inspection_templates FOR SELECT TO authenticated
  USING (private.restaurant_has_access(branch_id));
CREATE POLICY restaurant_inspection_items_member_read
  ON public.restaurant_inspection_items FOR SELECT TO authenticated
  USING (private.restaurant_has_access(branch_id));
CREATE POLICY restaurant_inspections_member_read
  ON public.restaurant_inspections FOR SELECT TO authenticated
  USING (private.restaurant_has_access(branch_id));
CREATE POLICY restaurant_inspection_results_member_read
  ON public.restaurant_inspection_results FOR SELECT TO authenticated
  USING (private.restaurant_has_access(branch_id));

CREATE OR REPLACE FUNCTION public.save_restaurant_inspection_template(
  p_branch_id uuid,
  p_actor_id uuid,
  p_template_id uuid,
  p_area_id uuid,
  p_name text,
  p_interval_minutes integer,
  p_is_active boolean,
  p_items jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  saved_id uuid;
  item_value jsonb;
  item_label text;
  item_index integer := 0;
BEGIN
  IF private.restaurant_user_role(p_branch_id, p_actor_id) NOT IN ('admin', 'supervisor') THEN
    RAISE EXCEPTION 'MANAGER_REQUIRED';
  END IF;
  IF length(trim(p_name)) NOT BETWEEN 2 AND 120
    OR p_interval_minutes IS NOT NULL AND p_interval_minutes NOT BETWEEN 1 AND 10080
    OR jsonb_typeof(coalesce(p_items, '[]'::jsonb)) <> 'array'
    OR jsonb_array_length(coalesce(p_items, '[]'::jsonb)) < 1
    OR jsonb_array_length(coalesce(p_items, '[]'::jsonb)) > 100 THEN
    RAISE EXCEPTION 'INVALID_INSPECTION_TEMPLATE';
  END IF;
  IF p_area_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.restaurant_areas
    WHERE branch_id = p_branch_id AND id = p_area_id AND is_active
  ) THEN RAISE EXCEPTION 'INVALID_INSPECTION_AREA'; END IF;

  IF p_template_id IS NULL THEN
    INSERT INTO public.restaurant_inspection_templates(
      branch_id, area_id, name, inspection_interval_minutes, is_active, created_by
    ) VALUES (
      p_branch_id, p_area_id, trim(p_name), p_interval_minutes, coalesce(p_is_active, true), p_actor_id
    ) RETURNING id INTO saved_id;
  ELSE
    UPDATE public.restaurant_inspection_templates SET
      area_id = p_area_id, name = trim(p_name),
      inspection_interval_minutes = p_interval_minutes,
      is_active = coalesce(p_is_active, true), updated_at = now()
    WHERE branch_id = p_branch_id AND id = p_template_id
    RETURNING id INTO saved_id;
    IF saved_id IS NULL THEN RAISE EXCEPTION 'INSPECTION_TEMPLATE_NOT_FOUND'; END IF;
    UPDATE public.restaurant_inspection_items SET is_active = false
    WHERE branch_id = p_branch_id AND template_id = saved_id AND is_active;
  END IF;

  FOR item_value IN SELECT value FROM jsonb_array_elements(coalesce(p_items, '[]'::jsonb))
  LOOP
    item_label := trim(coalesce(item_value->>'label', ''));
    IF length(item_label) NOT BETWEEN 2 AND 180 THEN RAISE EXCEPTION 'INVALID_INSPECTION_ITEM'; END IF;
    INSERT INTO public.restaurant_inspection_items(branch_id, template_id, label, sort_order)
    VALUES (p_branch_id, saved_id, item_label, item_index);
    item_index := item_index + 1;
  END LOOP;
  RETURN saved_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.record_restaurant_area_inspection(
  p_branch_id uuid,
  p_actor_id uuid,
  p_template_id uuid,
  p_client_event_id uuid,
  p_results jsonb,
  p_note text DEFAULT '',
  p_occurred_at timestamptz DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  branch_timezone text;
  existing_row public.restaurant_inspections%ROWTYPE;
  saved_row public.restaurant_inspections%ROWTYPE;
  item_value jsonb;
  selected_item public.restaurant_inspection_items%ROWTYPE;
  item_uuid uuid;
  result_state text;
  result_note text;
  active_item_count integer;
  result_count integer;
  distinct_item_count integer;
  attention_count integer := 0;
  inspection_at timestamptz := coalesce(p_occurred_at, now());
BEGIN
  IF private.restaurant_user_role(p_branch_id, p_actor_id) IS NULL THEN
    RAISE EXCEPTION 'BRANCH_ACCESS_REQUIRED';
  END IF;
  IF p_client_event_id IS NULL OR jsonb_typeof(coalesce(p_results, '[]'::jsonb)) <> 'array'
    OR jsonb_array_length(coalesce(p_results, '[]'::jsonb)) = 0
    OR length(coalesce(p_note, '')) > 1000 THEN
    RAISE EXCEPTION 'INVALID_INSPECTION';
  END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_branch_id::text || p_client_event_id::text, 0)
  );
  SELECT * INTO existing_row FROM public.restaurant_inspections
  WHERE branch_id = p_branch_id AND client_event_id = p_client_event_id;
  IF existing_row.id IS NOT NULL THEN
    IF existing_row.inspector_id <> p_actor_id OR existing_row.template_id <> p_template_id
      OR existing_row.note IS DISTINCT FROM trim(coalesce(p_note, ''))
      OR (SELECT count(*) FROM public.restaurant_inspection_results
        WHERE branch_id = p_branch_id AND inspection_id = existing_row.id)
        <> pg_catalog.jsonb_array_length(coalesce(p_results, '[]'::jsonb))
      OR EXISTS (
        SELECT 1
        FROM pg_catalog.jsonb_array_elements(coalesce(p_results, '[]'::jsonb)) AS supplied(value)
        LEFT JOIN public.restaurant_inspection_results AS recorded
          ON recorded.branch_id = p_branch_id
          AND recorded.inspection_id = existing_row.id
          AND recorded.item_id = (supplied.value->>'item_id')::uuid
        WHERE recorded.id IS NULL
          OR recorded.result_state IS DISTINCT FROM supplied.value->>'result_state'
          OR recorded.note IS DISTINCT FROM trim(coalesce(supplied.value->>'note', ''))
      ) THEN
      RAISE EXCEPTION 'IDEMPOTENCY_KEY_REUSED';
    END IF;
    RETURN pg_catalog.jsonb_build_object(
      'inspection_id', existing_row.id, 'duplicate', true,
      'needs_attention_count', existing_row.needs_attention_count
    );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.restaurant_inspection_templates
    WHERE branch_id = p_branch_id AND id = p_template_id AND is_active
  ) THEN RAISE EXCEPTION 'INSPECTION_TEMPLATE_UNAVAILABLE'; END IF;
  SELECT timezone INTO branch_timezone FROM public.restaurant_branches
  WHERE id = p_branch_id AND is_active;
  IF branch_timezone IS NULL THEN RAISE EXCEPTION 'BRANCH_NOT_FOUND'; END IF;

  SELECT count(*) INTO active_item_count FROM public.restaurant_inspection_items
  WHERE branch_id = p_branch_id AND template_id = p_template_id AND is_active;
  SELECT pg_catalog.jsonb_array_length(p_results), count(DISTINCT value->>'item_id')
    INTO result_count, distinct_item_count
  FROM pg_catalog.jsonb_array_elements(p_results);
  IF result_count <> active_item_count OR distinct_item_count <> result_count THEN
    RAISE EXCEPTION 'INSPECTION_ITEMS_INCOMPLETE';
  END IF;
  SELECT count(*) INTO attention_count
  FROM pg_catalog.jsonb_array_elements(p_results)
  WHERE value->>'result_state' = 'needs_attention';

  INSERT INTO public.restaurant_inspections(
    branch_id, template_id, inspector_id, client_event_id, inspection_date, inspected_at, note,
    needs_attention_count
  ) VALUES (
    p_branch_id, p_template_id, p_actor_id, p_client_event_id,
    (inspection_at AT TIME ZONE branch_timezone)::date, inspection_at, trim(coalesce(p_note, '')),
    attention_count
  ) RETURNING * INTO saved_row;

  FOR item_value IN SELECT value FROM pg_catalog.jsonb_array_elements(p_results)
  LOOP
    item_uuid := (item_value->>'item_id')::uuid;
    SELECT * INTO selected_item FROM public.restaurant_inspection_items
    WHERE branch_id = p_branch_id AND template_id = p_template_id
      AND id = item_uuid AND is_active;
    IF selected_item.id IS NULL THEN RAISE EXCEPTION 'INVALID_INSPECTION_ITEM'; END IF;
    result_state := item_value->>'result_state';
    IF result_state NOT IN ('ok', 'needs_attention', 'not_applicable') THEN
      RAISE EXCEPTION 'INVALID_INSPECTION_RESULT';
    END IF;
    result_note := trim(coalesce(item_value->>'note', ''));
    IF length(result_note) > 500 THEN RAISE EXCEPTION 'INVALID_INSPECTION_NOTE'; END IF;
    INSERT INTO public.restaurant_inspection_results(
      branch_id, inspection_id, item_id, item_label, result_state, note
    ) VALUES (
      p_branch_id, saved_row.id, selected_item.id, selected_item.label, result_state, result_note
    );
  END LOOP;
  RETURN pg_catalog.jsonb_build_object(
    'inspection_id', saved_row.id, 'duplicate', false,
    'needs_attention_count', attention_count
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.notify_restaurant_inspection_attention()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  template_name text;
BEGIN
  UPDATE public.restaurant_inspection_templates
  SET last_inspected_at = GREATEST(COALESCE(last_inspected_at, NEW.inspected_at), NEW.inspected_at)
  WHERE branch_id = NEW.branch_id AND id = NEW.template_id;
  IF NEW.needs_attention_count > 0 THEN
    SELECT name INTO template_name FROM public.restaurant_inspection_templates
    WHERE branch_id = NEW.branch_id AND id = NEW.template_id;
    INSERT INTO public.restaurant_notifications(
      branch_id, recipient_id, notification_type, title, body, entity_type, entity_id, data
    )
    SELECT NEW.branch_id, member.user_id, 'inspection_attention', 'Inspección requiere atención',
      pg_catalog.concat(template_name, ': ', NEW.needs_attention_count, ' elemento(s) requieren revisión.'),
      'inspection', NEW.id,
      pg_catalog.jsonb_build_object('inspection_id', NEW.id, 'template_id', NEW.template_id,
        'needs_attention_count', NEW.needs_attention_count)
    FROM public.restaurant_memberships AS member
    WHERE member.branch_id = NEW.branch_id AND member.is_active
      AND member.access_role IN ('admin', 'supervisor')
      AND member.user_id <> NEW.inspector_id;
  END IF;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.save_restaurant_inspection_template(uuid, uuid, uuid, uuid, text, integer, boolean, jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.record_restaurant_area_inspection(uuid, uuid, uuid, uuid, jsonb, text, timestamptz) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.notify_restaurant_inspection_attention() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.save_restaurant_inspection_template(uuid, uuid, uuid, uuid, text, integer, boolean, jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.record_restaurant_area_inspection(uuid, uuid, uuid, uuid, jsonb, text, timestamptz) TO service_role;

CREATE TRIGGER restaurant_inspection_attention_notification
  AFTER INSERT ON public.restaurant_inspections
  FOR EACH ROW EXECUTE FUNCTION public.notify_restaurant_inspection_attention();

DO $$
DECLARE
  table_name text;
BEGIN
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_publication WHERE pubname = 'supabase_realtime') THEN
    FOREACH table_name IN ARRAY ARRAY[
      'restaurant_inspection_templates', 'restaurant_inspection_items',
      'restaurant_inspections', 'restaurant_inspection_results'
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
