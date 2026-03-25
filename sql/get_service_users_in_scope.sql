-- FUNCTION: config.get_service_users_in_scope(text, text)
-- Returns the service-level scope for a user as (personio_user_id, connected_service,
-- service_user_id, start_date, end_date). Each row represents one person's mapping
-- to a service system and the period they were under this manager's scope.
--
-- NULL end_date means the person is still active in this scope.
--
-- DEPLOY ORDER: config.get_person_scope_by_fullname must be deployed first.

-- DROP FUNCTION IF EXISTS config.get_service_users_in_scope(text, text);

CREATE OR REPLACE FUNCTION config.get_service_users_in_scope(
	full_name text,
	user_role text)
    RETURNS TABLE(personio_user_id bigint, connected_service text, service_user_id bigint, start_date date, end_date date)
    LANGUAGE 'plpgsql'
    COST 100
    STABLE PARALLEL UNSAFE
    ROWS 1000

AS $BODY$
DECLARE
    effective_full_name TEXT;
BEGIN
    -- Override full_name for privileged roles (perm_level >= 2) using config.shiny_user_roles as
    -- single source of truth. Note: Studyflix Placeholder must have full org coverage in
    -- Personio for privileged users to receive complete scope.
    IF EXISTS (SELECT 1 FROM config.shiny_user_roles WHERE role_name = user_role AND perm_level >= 2) THEN
        effective_full_name := 'Studyflix Placeholder';
    ELSE
        effective_full_name := full_name;
    END IF;

    RETURN QUERY
    SELECT m.personio_user_id, m.connected_service, m.service_user_id, s.start_date, s.end_date
    FROM mapping.vw_service_users m
    JOIN config.get_person_scope_by_fullname(effective_full_name) s ON s.person_id = m.personio_user_id;
END;
$BODY$;

ALTER FUNCTION config.get_service_users_in_scope(text, text)
    OWNER TO postgres;