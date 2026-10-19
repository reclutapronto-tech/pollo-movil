-- ========================================================
-- Migration: 20260403000004_api_guards
-- Purpose:   Add idempotency storage, basic request logging, and cross-partition dedupe guards.
-- ========================================================

CREATE TABLE api_idempotency_keys (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  endpoint text NOT NULL,
  idempotency_key text NOT NULL,
  request_hash text NOT NULL,
  response_status integer NOT NULL,
  response_body jsonb NOT NULL,
  request_id text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT NOW(),
  UNIQUE (user_id, endpoint, idempotency_key)
);

CREATE INDEX idx_api_idempotency_lookup
  ON api_idempotency_keys(user_id, endpoint, idempotency_key);

CREATE INDEX idx_api_idempotency_created_at
  ON api_idempotency_keys(created_at);

CREATE TABLE api_request_logs (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  endpoint text NOT NULL,
  request_id text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_api_request_logs_lookup
  ON api_request_logs(user_id, endpoint, created_at DESC);

CREATE TABLE ingest_event_keys (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  event_type text NOT NULL,
  source_event_uuid uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT NOW(),
  UNIQUE (company_id, event_type, source_event_uuid)
);

CREATE INDEX idx_ingest_event_keys_lookup
  ON ingest_event_keys(company_id, event_type, created_at DESC);

