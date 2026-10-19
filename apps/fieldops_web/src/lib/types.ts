export interface TimelineEvent {
  id: string;
  company_id: string;
  job_id: string;
  user_id: string;
  event_type: string;
  occurred_at: string;
  payload: Record<string, unknown>;
}

export interface JobSummary {
  id: string;
  name: string;
  code: string;
  status: string;
  site_name: string | null;
  geofence_radius_m: number;
  active_worker_count?: number;
  last_activity_at?: string;
}

export interface WorkerStatus {
  user_id: string;
  full_name: string;
  role: string;
  is_clocked_in: boolean;
  active_job_name: string | null;
  last_clock_event_at: string | null;
  photo_count_today: number;
}
