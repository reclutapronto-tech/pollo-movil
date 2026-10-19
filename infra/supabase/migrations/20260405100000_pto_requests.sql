-- PTO / Time-Off Requests
-- Workers submit vacation/sick/personal leave requests.
-- Supervisors approve or deny.
-- Approved PTO deducts from available balance (tracked per company year).

CREATE TABLE IF NOT EXISTS pto_requests (
    id              uuid        NOT NULL DEFAULT gen_random_uuid(),
    company_id      uuid        NOT NULL REFERENCES companies(id),
    user_id         uuid        NOT NULL REFERENCES users(id),
    pto_type        text        NOT NULL CHECK (pto_type IN ('vacation', 'sick', 'personal')),
    start_date      date        NOT NULL,
    end_date        date        NOT NULL,
    day_count       int         NOT NULL GENERATED ALWAYS AS (end_date - start_date + 1) STORED,
    status          text        NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'denied', 'cancelled')),
    notes           text,
    decided_by      uuid        REFERENCES users(id),
    decided_at      timestamptz,
    decision_reason text,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT pto_dates_valid CHECK (end_date >= start_date),
    PRIMARY KEY (id)
);

-- Indexes for common query patterns
CREATE INDEX IF NOT EXISTS idx_pto_requests_user ON pto_requests(user_id, status, start_date DESC);
CREATE INDEX IF NOT EXISTS idx_pto_requests_company ON pto_requests(company_id, status, start_date DESC);

-- RLS
ALTER TABLE pto_requests ENABLE ROW LEVEL SECURITY;

-- Workers see their own PTO requests
CREATE POLICY "Worker sees own PTO"
    ON pto_requests FOR SELECT
    USING (company_id = public.current_company_id());

-- Workers can insert their own PTO requests
CREATE POLICY "Worker PTO insert"
    ON pto_requests FOR INSERT
    WITH CHECK (
        company_id = public.current_company_id()
        AND user_id = auth.uid()
        AND status = 'pending'
    );

-- Workers can cancel their own pending requests
CREATE POLICY "Worker PTO cancel"
    ON pto_requests FOR UPDATE
    USING (
        company_id = public.current_company_id()
        AND user_id = auth.uid()
        AND status = 'pending'
    )
    WITH CHECK (status = 'cancelled');

-- Supervisors/admins/owners can approve or deny
CREATE POLICY "Supervisor PTO decision"
    ON pto_requests FOR UPDATE
    USING (
        company_id = public.current_company_id()
        AND public.current_user_role() IN ('supervisor', 'admin', 'owner')
        AND status = 'pending'
    )
    WITH CHECK (
        status IN ('approved', 'denied')
        AND decided_by = auth.uid()
    );
