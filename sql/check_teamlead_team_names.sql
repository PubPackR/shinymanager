-- CHECK: every active Teamlead account still finds its team under the Entra login.
--
-- Under the Entra login, res_auth$user is the Personio full name
-- (first_name || ' ' || name). The level-1 pattern in the dashboards filters
-- `Team == user_name`, so that name must equal a team name in the open Sales
-- positions. Expected: one row per Teamlead account, every row team_found = true.
-- Read-only.

SELECT a.email,
       trim(concat(p.first_name, ' ', p.name)) AS full_name,
       EXISTS (
         SELECT 1
         FROM raw.personio_person_position_history h
         WHERE h.end_date IS NULL
           AND h.department = 'Sales'
           AND h.team = trim(concat(p.first_name, ' ', p.name))
       ) AS team_found
FROM config.shiny_accounts a
JOIN raw.personio_persons p ON p.id = a.personio_person_id
WHERE a.role_name = 'Teamlead'
  AND a.is_active
ORDER BY full_name;
