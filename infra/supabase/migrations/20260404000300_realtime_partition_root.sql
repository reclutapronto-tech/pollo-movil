-- ========================================================
-- Migration: 20260404000300_realtime_partition_root
-- Purpose:   Publish partitioned event changes via their parent table names
--            so Supabase Realtime subscriptions on clock_events/photo_events/
--            task_events/etc. receive inserts from partition children.
-- ========================================================

ALTER PUBLICATION supabase_realtime
SET (publish_via_partition_root = true);
