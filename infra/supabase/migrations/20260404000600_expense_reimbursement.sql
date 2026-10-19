-- ========================================================
-- Migration: 20260404000600_expense_reimbursement
-- Purpose:   Track reimbursement details for approved expenses
-- ========================================================

ALTER TABLE expense_events
ADD COLUMN IF NOT EXISTS reimbursed_at timestamptz,
ADD COLUMN IF NOT EXISTS reimbursed_by uuid REFERENCES users(id) ON DELETE SET NULL,
ADD COLUMN IF NOT EXISTS reimbursement_reference text,
ADD COLUMN IF NOT EXISTS reimbursement_notes text;

CREATE INDEX IF NOT EXISTS idx_expense_events_reimbursed_at
ON expense_events(reimbursed_at DESC NULLS LAST);
