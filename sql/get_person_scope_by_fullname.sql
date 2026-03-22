-- FUNCTION: config.get_person_scope_by_fullname(text)
-- Extends the original function to return one row per (person_id, month),
-- covering the full employment period of each scoped person (derived from
-- personio_person_position_history). This enables historical right-joins
-- in R modules using custom_get_user_scope(with_months = TRUE).

-- DROP FUNCTION IF EXISTS config.get_person_scope_by_fullname(text);

CREATE OR REPLACE FUNCTION config.get_person_scope_by_fullname(
	full_name text)
    RETURNS TABLE(person_id bigint, month date)
    LANGUAGE 'plpgsql'
    COST 100
    STABLE PARALLEL UNSAFE
    ROWS 1000

AS $BODY$
DECLARE
    v_start_person_id BIGINT;
BEGIN

	-- Lookup
    SELECT id INTO v_start_person_id
    FROM raw.personio_persons p
    WHERE concat(TRIM(p.first_name), ' ', TRIM(p.name)) = full_name;

	IF v_start_person_id IS NOT NULL THEN
		RETURN QUERY
		WITH RECURSIVE org_scope AS (
		    -- Direkte Untergebene (alle historisch, kein CURRENT_DATE Filter)
		    SELECT h1.person_id
		    FROM raw.personio_person_position_history h1
		    WHERE h1.superior = v_start_person_id

		    UNION

		    -- Rekursiv alle Untergebenen
		    SELECT h2.person_id
		    FROM raw.personio_person_position_history h2
		    JOIN org_scope o ON h2.superior = o.person_id
		),
		-- Beschäftigungszeitraum je Person aus position_history.
		-- bool_or(end_date IS NULL) prüft ob ein aktiver Eintrag existiert,
		-- da MAX() NULL-Werte ignoriert und sonst den falschen emp_end liefert.
		person_employment AS (
		    SELECT
		        o.person_id,
		        MIN(h.start_date)                                                                 AS emp_start,
		        CASE WHEN bool_or(h.end_date IS NULL) THEN CURRENT_DATE ELSE MAX(h.end_date) END  AS emp_end
		    FROM org_scope o
		    JOIN raw.personio_person_position_history h ON h.person_id = o.person_id
		    GROUP BY o.person_id

		    UNION ALL

		    -- Manager selbst einschließen
		    SELECT
		        v_start_person_id,
		        MIN(h.start_date),
		        CASE WHEN bool_or(h.end_date IS NULL) THEN CURRENT_DATE ELSE MAX(h.end_date) END
		    FROM raw.personio_person_position_history h
		    WHERE h.person_id = v_start_person_id
		)
		SELECT DISTINCT
		    pe.person_id,
		    date_trunc('month', gs.month)::date AS month
		FROM person_employment pe,
		LATERAL generate_series(
		    date_trunc('month', pe.emp_start)::date,
		    date_trunc('month', pe.emp_end)::date,
		    '1 month'::interval
		) AS gs(month);
	END IF;
END;

$BODY$;

ALTER FUNCTION config.get_person_scope_by_fullname(text)
    OWNER TO postgres;