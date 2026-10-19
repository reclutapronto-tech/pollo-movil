-- Add indexes on foreign-key columns that lacked a supporting index.
--
-- Unindexed FK columns force a sequential scan + row locks on the child table
-- whenever the parent row is deleted/updated (worst for ON DELETE CASCADE/SET
-- NULL), and slow ordinary joins/filters on those columns. List derived from a
-- live pg_constraint vs pg_index audit. Indexes on partitioned roots
-- (alert_events, correction_events, note_events, clock_events, photo_events,
-- shift_report_events, ot_approval_events) propagate to all partitions.

-- ── ON DELETE CASCADE (highest priority) ──────────────────────
CREATE INDEX IF NOT EXISTS idx_alert_events_job_id              ON public.alert_events(job_id);
CREATE INDEX IF NOT EXISTS idx_company_feature_overrides_flag   ON public.company_feature_overrides(flag_key);
CREATE INDEX IF NOT EXISTS idx_correction_events_job_id         ON public.correction_events(job_id);
CREATE INDEX IF NOT EXISTS idx_photo_comments_author_id         ON public.photo_comments(author_id);
CREATE INDEX IF NOT EXISTS idx_safety_checklists_job_id         ON public.safety_checklists(job_id);
CREATE INDEX IF NOT EXISTS idx_shift_swap_requests_shift_id     ON public.shift_swap_requests(shift_id);
CREATE INDEX IF NOT EXISTS idx_tasks_parent_task_id             ON public.tasks(parent_task_id);

-- ── ON DELETE SET NULL ────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_alert_events_user_id             ON public.alert_events(user_id);
CREATE INDEX IF NOT EXISTS idx_clock_events_device_id           ON public.clock_events(device_id);
CREATE INDEX IF NOT EXISTS idx_expense_events_decided_by        ON public.expense_events(decided_by);
CREATE INDEX IF NOT EXISTS idx_expense_events_media_asset_id    ON public.expense_events(media_asset_id);
CREATE INDEX IF NOT EXISTS idx_expense_events_reimbursed_by     ON public.expense_events(reimbursed_by);
CREATE INDEX IF NOT EXISTS idx_media_assets_original_media_id   ON public.media_assets(original_media_id);
CREATE INDEX IF NOT EXISTS idx_media_assets_stamped_media_id    ON public.media_assets(stamped_media_id);
CREATE INDEX IF NOT EXISTS idx_media_assets_thumbnail_media_id  ON public.media_assets(thumbnail_media_id);
CREATE INDEX IF NOT EXISTS idx_note_events_task_id              ON public.note_events(task_id);
CREATE INDEX IF NOT EXISTS idx_photo_events_device_id           ON public.photo_events(device_id);
CREATE INDEX IF NOT EXISTS idx_photo_reviews_reviewed_by        ON public.photo_reviews(reviewed_by);
CREATE INDEX IF NOT EXISTS idx_schedule_shifts_published_by     ON public.schedule_shifts(published_by);
CREATE INDEX IF NOT EXISTS idx_shift_swap_requests_swap_with    ON public.shift_swap_requests(swap_with_user_id);
CREATE INDEX IF NOT EXISTS idx_time_corrections_decided_by      ON public.time_corrections(decided_by);

-- ── ON DELETE RESTRICT / NO ACTION (join performance) ─────────
CREATE INDEX IF NOT EXISTS idx_alert_events_resolved_by         ON public.alert_events(resolved_by);
CREATE INDEX IF NOT EXISTS idx_assignments_assigned_by          ON public.assignments(assigned_by);
CREATE INDEX IF NOT EXISTS idx_correction_events_corrected_by   ON public.correction_events(corrected_by);
CREATE INDEX IF NOT EXISTS idx_job_budgets_created_by           ON public.job_budgets(created_by);
CREATE INDEX IF NOT EXISTS idx_job_share_tokens_created_by      ON public.job_share_tokens(created_by);
CREATE INDEX IF NOT EXISTS idx_ot_approval_events_approver_id   ON public.ot_approval_events(approver_id);
CREATE INDEX IF NOT EXISTS idx_ot_approval_events_worker_id     ON public.ot_approval_events(worker_id);
CREATE INDEX IF NOT EXISTS idx_photo_comment_mentions_company   ON public.photo_comment_mentions(company_id);
CREATE INDEX IF NOT EXISTS idx_photo_events_media_asset_id      ON public.photo_events(media_asset_id);
CREATE INDEX IF NOT EXISTS idx_photo_galleries_created_by       ON public.photo_galleries(created_by);
CREATE INDEX IF NOT EXISTS idx_photo_tags_created_by            ON public.photo_tags(created_by);
CREATE INDEX IF NOT EXISTS idx_platform_admin_invites_created_by ON public.platform_admin_invites(created_by);
CREATE INDEX IF NOT EXISTS idx_projects_created_by              ON public.projects(created_by);
CREATE INDEX IF NOT EXISTS idx_pto_requests_decided_by          ON public.pto_requests(decided_by);
CREATE INDEX IF NOT EXISTS idx_schedule_shifts_created_by       ON public.schedule_shifts(created_by);
CREATE INDEX IF NOT EXISTS idx_shift_report_events_foreman_id   ON public.shift_report_events(foreman_id);
CREATE INDEX IF NOT EXISTS idx_shift_swap_requests_decided_by   ON public.shift_swap_requests(decided_by);
CREATE INDEX IF NOT EXISTS idx_tasks_completed_by               ON public.tasks(completed_by);
CREATE INDEX IF NOT EXISTS idx_time_corrections_created_by      ON public.time_corrections(created_by);
CREATE INDEX IF NOT EXISTS idx_timecard_signatures_supervisor   ON public.timecard_signatures(supervisor_id);
CREATE INDEX IF NOT EXISTS idx_work_permits_created_by          ON public.work_permits(created_by);
CREATE INDEX IF NOT EXISTS idx_work_permits_issued_by           ON public.work_permits(issued_by);
CREATE INDEX IF NOT EXISTS idx_work_permits_revoked_by          ON public.work_permits(revoked_by);
