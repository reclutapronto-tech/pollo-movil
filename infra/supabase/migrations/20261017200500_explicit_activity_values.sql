ALTER TABLE public.restaurant_activity_templates
  ALTER COLUMN estimated_minutes DROP DEFAULT,
  ALTER COLUMN difficulty DROP DEFAULT,
  ALTER COLUMN priority DROP DEFAULT;

ALTER TABLE public.restaurant_activity_zones
  ALTER COLUMN difficulty DROP DEFAULT;

ALTER TABLE public.restaurant_task_parts
  ALTER COLUMN difficulty DROP DEFAULT;
