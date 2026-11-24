-- Fill config.shiny_accounts and config.shiny_app_access from the temp view
-- tmp_shiny_account_match.
--
-- Run in the SAME DBeaver session right after check_shiny_accounts.sql, and
-- only once its checks 3a-3c are understood. Only accounts with status 'ok'
-- are filled. Re-running is safe: existing e-mails and app grants are skipped.
--
-- Runs in one transaction; it ends with ROLLBACK so a first run changes
-- nothing. Look at the target-state queries, then replace ROLLBACK by COMMIT
-- and run again.

BEGIN;

-- Roles used by the accounts but missing in config.shiny_user_roles get the
-- level the R fallback already gives them (custom_functions.R, TRUE ~ 0).
INSERT INTO config.shiny_user_roles (role_name, perm_level)
SELECT DISTINCT permission, 0
FROM tmp_shiny_account_match
WHERE status = 'ok'
ON CONFLICT (role_name) DO NOTHING;

INSERT INTO config.shiny_accounts (email, personio_person_id, role_name)
SELECT email, person_id, permission
FROM tmp_shiny_account_match
WHERE status = 'ok'
ON CONFLICT (email) DO NOTHING;

-- One row per app as listed in the applications column; _test instances are
-- listed there separately and stay separate rows.
INSERT INTO config.shiny_app_access (account_id, app_name)
SELECT DISTINCT a.id, trim(app.app_name)
FROM tmp_shiny_account_match m
JOIN config.shiny_accounts a ON a.email = m.email
CROSS JOIN LATERAL regexp_split_to_table(coalesce(m.applications, ''), ';') AS app(app_name)
WHERE m.status = 'ok'
  AND trim(app.app_name) <> ''
ON CONFLICT (account_id, app_name) DO NOTHING;

-- ---------------------------------------------------------------------------
-- Target state
-- ---------------------------------------------------------------------------

-- Accounts: expected = number of 'ok' rows in check 3e
SELECT count(*) AS accounts FROM config.shiny_accounts;

-- App grants per account against the applications column of the SQLite.
-- Every row must show diff = 0.
SELECT m.account_name,
       m.email,
       (SELECT count(DISTINCT trim(x))
          FROM regexp_split_to_table(coalesce(m.applications, ''), ';') AS x
         WHERE trim(x) <> '') AS apps_in_sqlite,
       count(acc.id) AS apps_in_config,
       (SELECT count(DISTINCT trim(x))
          FROM regexp_split_to_table(coalesce(m.applications, ''), ';') AS x
         WHERE trim(x) <> '') - count(acc.id) AS diff
FROM tmp_shiny_account_match m
JOIN config.shiny_accounts a ON a.email = m.email
LEFT JOIN config.shiny_app_access acc ON acc.account_id = a.id
WHERE m.status = 'ok'
GROUP BY m.account_name, m.email, m.applications
ORDER BY diff DESC, m.account_name;

ROLLBACK;  -- replace by COMMIT once the target state is right
