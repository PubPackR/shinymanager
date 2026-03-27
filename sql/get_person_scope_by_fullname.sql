-- FUNCTION: config.get_person_scope_by_fullname(text)
-- Returns the scope of a manager as (person_id, start_date, end_date) periods.
-- Each row represents one continuous period during which a person was under
-- the given manager (directly or indirectly). Overlapping periods per person
-- are merged into a single continuous interval.
--
-- Key design decisions:
-- - Uses actual position_history dates instead of MIN/MAX employment range.
--   This correctly handles team changes: a person who moves from Team A to Team B
--   only appears in Team A's scope for the period they were actually there.
-- - For indirect reports, dates are intersected through the hierarchy recursively.
-- - Sentinel date '9999-12-31' is used internally for NULL end_dates (still active),
--   converted back to NULL in the final output.
-- - UNION (deduplicating) is used in the recursive CTE to prevent infinite recursion
--   if a cycle exists in position_history data.
-- - Overlapping periods per person are merged via gaps-and-islands approach.
-- - The manager themselves is included for the periods they actually had direct
--   reports (not their full employment period).

-- DROP FUNCTION IF EXISTS config.get_person_scope_by_fullname(text);

CREATE OR REPLACE FUNCTION config.get_person_scope_by_fullname(
	full_name text)
    RETURNS TABLE(person_id bigint, start_date date, end_date date)
    LANGUAGE 'plpgsql'
    COST 100
    STABLE PARALLEL UNSAFE
    ROWS 1000

AS $BODY$
#variable_conflict use_column
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

            UNION  -- deduplicating to prevent infinite recursion on cyclic data

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
        ),

        -- Merge overlapping/adjacent periods per person (gaps-and-islands)
        scope_islands AS (
            SELECT
                person_id,
                start_date,
                end_date,
                start_date > COALESCE(
                    LAG(end_date) OVER (PARTITION BY person_id ORDER BY start_date),
                    start_date - 1
                ) AS is_new_island
            FROM (SELECT DISTINCT person_id, start_date, end_date FROM org_scope) d
        ),
        scope_grouped AS (
            SELECT
                person_id,
                start_date,
                end_date,
                SUM(is_new_island::int) OVER (PARTITION BY person_id ORDER BY start_date) AS grp
            FROM scope_islands
        ),
        scope_merged AS (
            SELECT
                person_id,
                MIN(start_date) AS start_date,
                MAX(end_date)   AS end_date
            FROM scope_grouped
            GROUP BY person_id, grp
        ),

        -- Manager's own scope periods: the periods during which they actually had
        -- direct reports (derived from position_history entries pointing to them).
        -- Uses gaps-and-islands to merge adjacent/overlapping management periods.
        manager_islands AS (
            SELECT
                start_date,
                end_date,
                start_date > COALESCE(
                    LAG(end_date) OVER (ORDER BY start_date),
                    start_date - 1
                ) AS is_new_island
            FROM (
                SELECT DISTINCT
                    start_date,
                    COALESCE(end_date, '9999-12-31'::date) AS end_date
                FROM raw.personio_person_position_history
                WHERE superior = v_start_person_id
            ) d
        ),
        manager_grouped AS (
            SELECT
                start_date,
                end_date,
                SUM(is_new_island::int) OVER (ORDER BY start_date) AS grp
            FROM manager_islands
        ),
        manager_periods AS (
            SELECT
                MIN(start_date) AS start_date,
                MAX(end_date)   AS end_date
            FROM manager_grouped
            GROUP BY grp
        )

        -- Direct/indirect reports with merged periods
        SELECT
            person_id,
            start_date,
            NULLIF(end_date, '9999-12-31'::date) AS end_date
        FROM scope_merged

        UNION ALL

        -- Manager themselves — one row per continuous management period
        SELECT
            v_start_person_id                                                       AS person_id,
            start_date,
            NULLIF(end_date, '9999-12-31'::date)                                   AS end_date
        FROM manager_periods;

    END IF;
END;

$BODY$;

ALTER FUNCTION config.get_person_scope_by_fullname(text)
    OWNER TO postgres;