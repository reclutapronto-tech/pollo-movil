export interface Worker {
  id: string;
  full_name: string;
  role: string;
}

export interface Job {
  id: string;
  name: string;
  code: string;
}

export interface ScheduleEntry {
  id: string;
  worker_id: string;
  worker_name: string;
  job_id: string;
  job_name: string;
  job_code?: string | null;
  date: string;
  start_time: string;
  end_time: string;
  status: "draft" | "published";
  notes?: string | null;
  published_at?: string | null;
  published_by?: string | null;
}

export interface PtoRequest {
  id: string;
  user_id: string;
  status: string;
  start_date: string;
  end_date: string;
}

export type ViewMode = "day" | "week" | "twoWeek" | "month";

export const VIEW_MODES: ViewMode[] = ["day", "week", "twoWeek", "month"];

export interface ConflictFlags {
  pto: boolean;
  doubleBooked: boolean;
  overtime: boolean;
}
