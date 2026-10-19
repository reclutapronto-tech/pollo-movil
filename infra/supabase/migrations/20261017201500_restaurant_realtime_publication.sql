DO $$
DECLARE
  table_name text;
  realtime_tables text[] := ARRAY[
    'restaurant_branches',
    'restaurant_areas',
    'restaurant_positions',
    'restaurant_memberships',
    'restaurant_shifts',
    'restaurant_shift_breaks',
    'restaurant_activity_templates',
    'restaurant_activity_positions',
    'restaurant_activity_zones',
    'restaurant_waste_positions',
    'restaurant_tasks',
    'restaurant_task_parts',
    'restaurant_incidents',
    'restaurant_absences',
    'restaurant_waste_bins',
    'restaurant_waste_inspections',
    'restaurant_waste_inspection_results',
    'restaurant_inspection_templates',
    'restaurant_inspection_items',
    'restaurant_inspections',
    'restaurant_inspection_results',
    'restaurant_shift_handoffs',
    'restaurant_notifications'
  ];
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_publication WHERE pubname = 'supabase_realtime') THEN
    RETURN;
  END IF;

  FOREACH table_name IN ARRAY realtime_tables LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_publication_tables
      WHERE pubname = 'supabase_realtime'
        AND schemaname = 'public'
        AND tablename = table_name
    ) THEN
      EXECUTE pg_catalog.format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', table_name);
    END IF;
  END LOOP;
END;
$$;

GRANT SELECT ON TABLE
  public.restaurant_branches,
  public.restaurant_areas,
  public.restaurant_positions,
  public.restaurant_memberships,
  public.restaurant_shifts,
  public.restaurant_shift_breaks,
  public.restaurant_activity_templates,
  public.restaurant_activity_positions,
  public.restaurant_activity_zones,
  public.restaurant_tasks,
  public.restaurant_task_parts,
  public.restaurant_incidents,
  public.restaurant_absences,
  public.restaurant_waste_bins,
  public.restaurant_waste_positions,
  public.restaurant_waste_inspections,
  public.restaurant_waste_inspection_results,
  public.restaurant_inspection_templates,
  public.restaurant_inspection_items,
  public.restaurant_inspections,
  public.restaurant_inspection_results,
  public.restaurant_shift_handoffs,
  public.restaurant_notifications
TO authenticated;
