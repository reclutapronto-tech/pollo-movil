-- Background Jobs / Queuing Infrastructure
-- Provides a lightweight, Postgres-native job queue with claim/complete semantics
-- and exponential backoff retry.

CREATE TABLE IF NOT EXISTS background_jobs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  job_type TEXT NOT NULL,
  payload JSONB NOT NULL DEFAULT '{}',
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'running', 'completed', 'failed')),
  attempts INTEGER NOT NULL DEFAULT 0,
  max_attempts INTEGER NOT NULL DEFAULT 3,
  last_error TEXT,
  scheduled_for TIMESTAMPTZ NOT NULL DEFAULT now(),
  started_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_background_jobs_status ON background_jobs(status, scheduled_for);
CREATE INDEX IF NOT EXISTS idx_background_jobs_type ON background_jobs(job_type);

-- Function to enqueue a job
CREATE OR REPLACE FUNCTION enqueue_job(p_type TEXT, p_payload JSONB DEFAULT '{}', p_delay INTERVAL DEFAULT '0 seconds')
RETURNS UUID AS $$
DECLARE
  job_id UUID;
BEGIN
  INSERT INTO background_jobs (job_type, payload, scheduled_for)
  VALUES (p_type, p_payload, now() + p_delay)
  RETURNING id INTO job_id;
  RETURN job_id;
END;
$$ LANGUAGE plpgsql;

-- Function to claim next job (for worker/cron to call)
CREATE OR REPLACE FUNCTION claim_next_job(p_types TEXT[] DEFAULT NULL)
RETURNS SETOF background_jobs AS $$
BEGIN
  RETURN QUERY
  UPDATE background_jobs
  SET status = 'running', started_at = now(), attempts = attempts + 1
  WHERE id = (
    SELECT id FROM background_jobs
    WHERE status = 'pending'
      AND scheduled_for <= now()
      AND (p_types IS NULL OR job_type = ANY(p_types))
    ORDER BY scheduled_for ASC
    LIMIT 1
    FOR UPDATE SKIP LOCKED
  )
  RETURNING *;
END;
$$ LANGUAGE plpgsql;

-- Function to complete a job
CREATE OR REPLACE FUNCTION complete_job(p_id UUID, p_error TEXT DEFAULT NULL)
RETURNS VOID AS $$
BEGIN
  IF p_error IS NULL THEN
    UPDATE background_jobs SET status = 'completed', completed_at = now() WHERE id = p_id;
  ELSE
    UPDATE background_jobs
    SET status = CASE WHEN attempts >= max_attempts THEN 'failed' ELSE 'pending' END,
        last_error = p_error,
        scheduled_for = now() + (power(2, attempts) || ' seconds')::interval
    WHERE id = p_id;
  END IF;
END;
$$ LANGUAGE plpgsql;
