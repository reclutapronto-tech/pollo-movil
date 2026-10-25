ALTER TABLE public.restaurant_waste_bins
  ADD COLUMN IF NOT EXISTS bag_change_activity_name text,
  ADD COLUMN IF NOT EXISTS bag_change_minutes integer,
  ADD COLUMN IF NOT EXISTS bag_change_difficulty smallint,
  ADD COLUMN IF NOT EXISTS bag_change_priority smallint;

ALTER TABLE public.restaurant_waste_bins
  ADD CONSTRAINT restaurant_waste_bins_task_name_check
    CHECK (bag_change_activity_name IS NULL OR length(trim(bag_change_activity_name)) BETWEEN 2 AND 120),
  ADD CONSTRAINT restaurant_waste_bins_task_minutes_check
    CHECK (bag_change_minutes IS NULL OR bag_change_minutes BETWEEN 1 AND 1440),
  ADD CONSTRAINT restaurant_waste_bins_task_difficulty_check
    CHECK (bag_change_difficulty IS NULL OR bag_change_difficulty BETWEEN 1 AND 5),
  ADD CONSTRAINT restaurant_waste_bins_task_priority_check
    CHECK (bag_change_priority IS NULL OR bag_change_priority BETWEEN 1 AND 5);

ALTER TABLE public.restaurant_tasks
  ALTER COLUMN estimated_minutes DROP DEFAULT,
  ALTER COLUMN difficulty DROP DEFAULT,
  ALTER COLUMN priority DROP DEFAULT;
