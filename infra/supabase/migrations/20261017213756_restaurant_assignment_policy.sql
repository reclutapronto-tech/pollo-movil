ALTER TABLE public.restaurant_branches
  ADD COLUMN assignment_load_balance_weight integer NOT NULL DEFAULT 100
    CHECK (assignment_load_balance_weight BETWEEN 0 AND 1000),
  ADD COLUMN assignment_heavy_rotation_weight integer NOT NULL DEFAULT 60
    CHECK (assignment_heavy_rotation_weight BETWEEN 0 AND 1000),
  ADD COLUMN assignment_priority_weight integer NOT NULL DEFAULT 100
    CHECK (assignment_priority_weight BETWEEN 0 AND 1000);

COMMENT ON COLUMN public.restaurant_branches.assignment_load_balance_weight IS
  'Branch-configurable soft weight for balancing weighted assigned workload; 0 disables this preference.';
COMMENT ON COLUMN public.restaurant_branches.assignment_heavy_rotation_weight IS
  'Branch-configurable soft penalty for assigning heavy work to employees with recent heavy-task history.';
COMMENT ON COLUMN public.restaurant_branches.assignment_priority_weight IS
  'Branch-configurable medium penalty multiplier for leaving higher-priority units unassigned.';
