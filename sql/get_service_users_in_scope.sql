-- FUNCTION: public.get_service_users_in_scope(text, text)
-- Extends the original function to also return a `month` column by joining
-- with the updated get_person_scope_by_fullname(), which now returns
-- one row per (person_id, month). This allows R modules to perform
-- historical right-joins via custom_get_user_scope(with_months = TRUE).
--
-- DEPLOY ORDER: create_user_roles.sql + get_person_scope_by_fullname.sql must be deployed first.

-- DROP FUNCTION IF EXISTS public.get_service_users_in_scope(text, text);

CREATE OR REPLACE FUNCTION public.get_service_users_in_scope(
	full_name text,
	user_role text)
    RETURNS TABLE(personio_user_id bigint, connected_service text, service_user_id bigint, month date)
    LANGUAGE 'plpgsql'
    COST 100
    STABLE PARALLEL UNSAFE
    ROWS 1000

AS $BODY$
DECLARE
    effective_full_name TEXT;
BEGIN
    -- Override full_name for privileged roles (perm_level >= 2) using public.user_roles as
    -- single source of truth. Note: Studyflix Placeholder must have full org coverage in
    -- Personio for privileged users to receive complete scope.
    IF EXISTS (SELECT 1 FROM public.user_roles WHERE role_name = user_role AND perm_level >= 2) THEN
        effective_full_name := 'Studyflix Placeholder';
    ELSE
        effective_full_name := full_name;
    END IF;

    RETURN QUERY
    SELECT m.personio_user_id, m.connected_service, m.service_user_id, s.month
    FROM mapping.vw_service_users m
    JOIN get_person_scope_by_fullname(effective_full_name) s ON s.person_id = m.personio_user_id;
END;
$BODY$;

ALTER FUNCTION public.get_service_users_in_scope(text, text)
    OWNER TO postgres;
