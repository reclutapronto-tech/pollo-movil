ALTER TABLE public.restaurant_shifts
  DROP CONSTRAINT restaurant_shifts_status_check;

ALTER TABLE public.restaurant_shifts
  ADD CONSTRAINT restaurant_shifts_status_check
  CHECK (status IN ('draft', 'published', 'cancelled'));
