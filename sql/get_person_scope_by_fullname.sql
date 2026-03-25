-- FUNCTION: config.get_person_scope_by_fullname(text)
-- Returns the scope of a manager as (person_id, start_date, end_date) periods.
-- Each row represents one continuous period during which a person was under
-- the given manager (directly or indirectly).
--
-- Key design decisions:
-- - Uses actual position_history dates instead of MIN/MAX employment range.
--   This correctly handles team changes: a person who moves from Team A to Team B
--   only appears in Team A's scope for the period they were actually there.
-- - For indirect reports, dates are intersected through the hierarchy recursively.
-- - Sentinel date '9999-12-31' is used internally for NULL end_dates (still active),
--   converted back to NULL in the final output.
-- - UNION ALL is used in the recursive CTE; cycles in position data would cause
--   infinite recursion. Org chart data is assumed to be acyclic.

-- DROP FUNCTION IF EXISTS config.get_person_scope_by_fullname(text);

CREATE OR REPLACE FUNCTION config.get_person_scope_by_fullname(
	full_name text)
    RETURNS TABLE(person_id bigint, start_date date, end_date date)
    LANGUAGE 'plpgsql'
    COST 100
    STABLE PARALLEL UNSAFE
    ROWS 1000

AS $BODY$
DECLARE
    v_start_person_id BIGINT;
BEGIN

    SELECT id INTO v_start_person_id
    FROM raw.personio_persons p
    WHERE concat(TRIM(p.first_name), ' ', TRIM(p.name)) = full_name;

    IF v_start_person_id IS NOT NULL THEN
        RETURN QUERY
        WITH RECURSIVE org_scope AS (

            -- Anchor: direct reports — use their exact position history period
            SELECT
                h1.person_id,
                h1.start_date,
                COALESCE(h1.end_date, '9999-12-31'::date) AS end_date
            FROM raw.personio_person_position_history h1
            WHERE h1.superior = v_start_person_id

            UNION ALL

            -- Recursive: indirect reports — intersect their period with their
            -- direct superior's period in this scope
            SELECT
                h2.person_id,
                GREATEST(h2.start_date, o.start_date)                            AS start_date,
                LEAST(COALESCE(h2.end_date, '9999-12-31'::date), o.end_date)     AS end_date
            FROM raw.personio_person_position_history h2
            JOIN org_scope o ON h2.superior = o.person_id
            -- Only recurse when the intersection is non-empty
            WHERE GREATEST(h2.start_date, o.start_date)
                < LEAST(COALESCE(h2.end_date, '9999-12-31'::date), o.end_date)
        )

        SELECT DISTINCT
            s.person_id,
            s.start_date,
            NULLIF(s.end_date, '9999-12-31'::date) AS end_date
        FROM org_scope s

        UNION ALL

        -- Include the manager themselves for their full employment period
        SELECT
            v_start_person_id                                                        AS person_id,
            MIN(h.start_date)                                                        AS start_date,
            NULLIF(MAX(COALESCE(h.end_date, '9999-12-31'::date)), '9999-12-31'::date) AS end_date
        FROM raw.personio_person_position_history h
        WHERE h.person_id = v_start_person_id;

    END IF;
END;

$BODY$;

ALTER FUNCTION config.get_person_scope_by_fullname(text)
    OWNER TO postgres;