export interface CompanySummary {
  id: string;
  name: string;
  slug: string;
  status: string;
  payment_status: string;
  industry: string | null;
  logo_url: string | null;
  created_at: string;
  active_user_count: number;
  total_user_count: number;
}

export interface PlatformAdmin {
  id: string;
  email: string;
  full_name: string;
  role: string;
  is_active: boolean;
  created_at: string;
}

export interface CompanyUser {
  id: string;
  full_name: string;
  email: string | null;
  role: string;
  is_active: boolean;
  created_at: string;
}

export interface AuditLogEntry {
  id: string;
  action: string;
  actor_email: string;
  target_type: string;
  target_id: string;
  details: Record<string, unknown> | null;
  created_at: string;
}

export interface CompanyDetail {
  id: string;
  name: string;
  slug: string;
  status: string;
  payment_status: string;
  industry: string | null;
  logo_url: string | null;
  timezone: string | null;
  created_at: string;
  updated_at: string;
}
