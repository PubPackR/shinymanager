-- Load the shinymanager credentials into a temp table and check them against
-- Personio BEFORE filling config.shiny_accounts. Read-only apart from the temp
-- table.
--
-- Run in ONE DBeaver session, followed by fill_shiny_accounts.sql in the same
-- session: the temp table lives only as long as the connection.
--
-- Matching rule: an account name matches a Personio person when it equals
-- "first_name name" (case-insensitive, trimmed) or one of the person's aliases
-- in mapping.user_aliases. Only active persons are filled: not deleted in
-- Personio and with a position that has not ended.

-- ---------------------------------------------------------------------------
-- 1. Temp table with the export from export_shiny_credentials_sqlite.sql
-- ---------------------------------------------------------------------------

DROP TABLE IF EXISTS tmp_shiny_credentials;

CREATE TEMP TABLE tmp_shiny_credentials (
    account_name text,
    permission   text,
    applications text
);

INSERT INTO tmp_shiny_credentials (account_name, permission, applications) VALUES
-- >>> paste the values_list cell here, without a trailing comma <<<
;

-- ---------------------------------------------------------------------------
-- 2. Account -> Personio match, one row per account (temp view, reused by fill)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE TEMP VIEW tmp_shiny_account_match AS
WITH candidates AS (
    SELECT c.account_name, p.id AS person_id
    FROM tmp_shiny_credentials c
    JOIN raw.personio_persons p
      ON lower(trim(p.first_name) || ' ' || trim(p.name)) = lower(trim(c.account_name))
    UNION
    SELECT c.account_name, a.personio_person_id
    FROM tmp_shiny_credentials c
    JOIN mapping.user_aliases a
      ON lower(trim(a.alias)) = lower(trim(c.account_name))
),
activity AS (
    SELECT h.person_id,
           bool_or(h.end_date IS NULL OR h.end_date >= CURRENT_DATE) AS has_open_position,
           max(h.end_date) AS last_end_date
    FROM raw.personio_person_position_history h
    GROUP BY h.person_id
),
per_account AS (
    SELECT c.account_name,
           count(DISTINCT m.person_id) AS n_persons,
           min(m.person_id) AS person_id
    FROM tmp_shiny_credentials c
    LEFT JOIN candidates m ON m.account_name = c.account_name
    GROUP BY c.account_name
)
SELECT pa.account_name,
       c.permission,
       c.applications,
       pa.n_persons,
       CASE WHEN pa.n_persons = 1 THEN pa.person_id END AS person_id,
       lower(trim(p.email)) AS email,
       coalesce(p.is_deleted, false) AS is_deleted,
       coalesce(act.has_open_position, false) AS has_open_position,
       act.last_end_date,
       CASE
           WHEN pa.n_persons = 0 THEN 'no Personio match (technical or team account?)'
           WHEN pa.n_persons > 1 THEN 'several Personio matches'
           WHEN p.is_deleted OR NOT coalesce(act.has_open_position, false) THEN 'person has left'
           WHEN p.email IS NULL OR trim(p.email) = '' THEN 'no e-mail in Personio'
           ELSE 'ok'
       END AS status
FROM per_account pa
JOIN tmp_shiny_credentials c ON c.account_name = pa.account_name
LEFT JOIN raw.personio_persons p ON p.id = CASE WHEN pa.n_persons = 1 THEN pa.person_id END
LEFT JOIN activity act ON act.person_id = p.id;

-- ---------------------------------------------------------------------------
-- 3. Checks: everything that is not 'ok' is NOT filled
-- ---------------------------------------------------------------------------

-- 3a. Accounts that will not be filled, and why
SELECT status, account_name, permission, last_end_date
FROM tmp_shiny_account_match
WHERE status <> 'ok'
ORDER BY status, account_name;

-- 3b. Accounts that will be filled but whose e-mail is not @studyflix.de
--     (Entra may forward a different address, Q21)
SELECT account_name, email
FROM tmp_shiny_account_match
WHERE status = 'ok'
  AND email NOT LIKE '%@studyflix.de';

-- 3c. Two accounts that resolve to the same e-mail (would violate uq_shiny_accounts_email)
SELECT email, string_agg(account_name, ', ') AS accounts
FROM tmp_shiny_account_match
WHERE status = 'ok'
GROUP BY email
HAVING count(*) > 1;

-- 3d. Roles of accounts to be filled that are missing in config.shiny_user_roles
--     (fill_shiny_accounts.sql adds them with perm_level 0, Q22)
SELECT DISTINCT m.permission AS missing_role
FROM tmp_shiny_account_match m
LEFT JOIN config.shiny_user_roles r ON r.role_name = m.permission
WHERE m.status = 'ok'
  AND r.role_name IS NULL;

-- 3e. Summary
SELECT status, count(*) AS accounts
FROM tmp_shiny_account_match
GROUP BY status
ORDER BY status;
