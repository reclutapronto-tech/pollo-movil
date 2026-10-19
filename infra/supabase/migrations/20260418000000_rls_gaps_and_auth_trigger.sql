-- Migration: fill RLS gaps and add auth trigger for auto user profile creation

-- media_assets INSERT: any authenticated user within their company can upload
CREATE POLICY "Worker media asset insert"
ON public.media_assets FOR INSERT
TO authenticated
WITH CHECK (
  uploaded_by = auth.uid()
  AND current_company_id() IS NOT NULL
);

-- assignments write: supervisors and above can manage assignments
CREATE POLICY "Supervisor assignment insert"
ON public.assignments FOR INSERT
TO authenticated
WITH CHECK (
  current_user_role() IN ('owner','admin','supervisor','foreman')
  AND company_id = current_company_id()
);

CREATE POLICY "Supervisor assignment update"
ON public.assignments FOR UPDATE
TO authenticated
USING (
  current_user_role() IN ('owner','admin','supervisor','foreman')
  AND company_id = current_company_id()
);

CREATE POLICY "Supervisor assignment delete"
ON public.assignments FOR DELETE
TO authenticated
USING (
  current_user_role() IN ('owner','admin','supervisor','foreman')
  AND company_id = current_company_id()
);

-- tasks write: supervisors+ insert/update, admins+ delete
CREATE POLICY "Admin task insert"
ON public.tasks FOR INSERT
TO authenticated
WITH CHECK (
  current_user_role() IN ('owner','admin','supervisor')
  AND company_id = current_company_id()
);

CREATE POLICY "Admin task update"
ON public.tasks FOR UPDATE
TO authenticated
USING (
  current_user_role() IN ('owner','admin','supervisor')
  AND company_id = current_company_id()
);

CREATE POLICY "Admin task delete"
ON public.tasks FOR DELETE
TO authenticated
USING (
  current_user_role() IN ('owner','admin')
  AND company_id = current_company_id()
);

-- admin_audit_log: admins and owners read-only
CREATE POLICY "Admin audit log read"
ON public.admin_audit_log FOR SELECT
TO authenticated
USING (
  current_user_role() IN ('owner','admin')
  AND company_id = current_company_id()
);

-- service-only tables: deny all direct authenticated access
CREATE POLICY "No direct user access to background_jobs"
ON public.background_jobs FOR ALL
TO authenticated
USING (false);

CREATE POLICY "No direct user access to ingest_event_keys"
ON public.ingest_event_keys FOR ALL
TO authenticated
USING (false);

CREATE POLICY "No direct user access to platform_admins"
ON public.platform_admins FOR ALL
TO authenticated
USING (false);

CREATE POLICY "No direct user access to platform_admin_invites"
ON public.platform_admin_invites FOR ALL
TO authenticated
USING (false);

-- Auth trigger: auto-create public.users profile on new signup
-- Only fires when company_id and role are present in user metadata (admin-provisioned)
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id uuid;
  v_role user_role;
  v_full_name text;
BEGIN
  v_company_id := (NEW.raw_user_meta_data->>'company_id')::uuid;
  v_role := (NEW.raw_user_meta_data->>'role')::user_role;
  v_full_name := COALESCE(NEW.raw_user_meta_data->>'full_name', split_part(NEW.email, '@', 1));

  IF v_company_id IS NOT NULL AND v_role IS NOT NULL THEN
    INSERT INTO public.users (id, company_id, role, full_name, email, is_active)
    VALUES (NEW.id, v_company_id, v_role, v_full_name, NEW.email, true)
    ON CONFLICT (id) DO NOTHING;
  END IF;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();
