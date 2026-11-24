# Dashboard accounts, app access and audit logs in PostgreSQL (config)
Ticket: https://app.asana.com/0/0/1220826186115982/f (parent: https://app.asana.com/0/0/1220823360276345/f)

## Problem

Dashboard accounts, roles and app access live in `base-data/database/shiny_users.sqlite`
(table `credentials`), next to a password hash and an encrypted master key. The file sits on the
server and as copies on laptops. The login is a second password login behind the Entra
oauth2-proxy, keyed by a person's full name.

The parent ticket replaces this with a login by the Entra e-mail (`X-Forwarded-Email`). This ticket
(T2) builds the PostgreSQL side it needs and fills it once from the SQLite.

## Solution

- `sql/create_shiny_accounts.sql`: four tables in `config`.
  - `shiny_accounts`: one personal account per person, keyed by e-mail, with
    `personio_person_id` and `role_name` (FK `config.shiny_user_roles`) and `is_active`.
  - `shiny_app_access`: one row per account and app folder name; a `_test` instance is its own row.
  - `shiny_impersonation_log`, `shiny_login_log`: audit logs with e-mails as text and no foreign
    keys, so deleting an account keeps its history.
- Filling without personal data in the repo, in one DBeaver session:
  1. `sql/export_shiny_credentials_sqlite.sql` (SQLite) turns `credentials` into a VALUES list
     of user, permission and applications.
  2. `sql/check_shiny_accounts.sql` loads it into a temp table, matches each account to Personio
     (full name or `mapping.user_aliases`) and lists what will not be filled and why.
  3. `sql/fill_shiny_accounts.sql` adds missing roles with `perm_level` 0, fills accounts and app
     access for matched active persons, shows the target state and ends with `ROLLBACK` until the
     result is right.

## Decisions

- **Q20 Getting the data out of the SQLite:** (a) a SQLite query in DBeaver on a fresh copy
  generates the INSERT values; the copy is deleted afterwards.
- **Q21 Source of the e-mail:** `raw.personio_persons.email`; a check lists accounts whose
  address is not `@studyflix.de` before filling.
- **Q22 Missing roles:** roles used in the SQLite but missing in `config.shiny_user_roles` are
  added with `perm_level` 0.
- **Q23 Login history:** its table is part of this ticket.
- **Q24 Location:** `packages/shinymanager/sql/`.
- **Q25 Tables and keys:** `shiny_accounts`, `shiny_app_access` (a row per app and per `_test`),
  `shiny_impersonation_log` and `shiny_login_log` (text, no FK), `personio_person_id` named as in
  `mapping.user_aliases`.
- **Q26 Role name for empty roles:** `Mitarbeiter`, `perm_level` 0 (62 of 77 accounts in the
  trial run on 24.11.2026 had an empty role, which R treats as level 0).
- **Q27 The account with `Head of`:** migrated as `Headof` (level 2); `Head of` with a space
  never matched in R and gave level 0.

Earlier decisions from the analysis that shape this ticket (parent ticket): Q1 login by Entra
e-mail without password; Q8 login history starts new; Q9 tables via `/create-db-schema`; Q10 app
access as a table in `config`; Q11 product whitelist and admin list as a Secret Manager secret,
not in these tables; Q14 every impersonation is logged; Q15 `personio_person_id` stored on the
account.

## Affected

- New: `config.shiny_accounts`, `config.shiny_app_access`, `config.shiny_impersonation_log`,
  `config.shiny_login_log`.
- Written: `config.shiny_user_roles` (missing roles only).
- Read: `raw.personio_persons`, `raw.personio_person_position_history`, `mapping.user_aliases`,
  `shiny_users.sqlite` (`credentials`: user, permission, applications only).
- Repo: `packages/shinymanager`, folder `sql/`. No R code changes; nothing reads the new tables
  yet (that is T3/T4).

## Out of scope

- Reading the new tables in R, the new login, the account display, product mode and
  impersonation (T3); the admin app (T4); switching the dashboards over and deleting the SQLite
  files (T5).
- Shared and team accounts (`admin`, `produkt`, team logins): not migrated; they fall out as
  "no Personio match". Replacing them is the matrix clean-up ticket.
- Accounts of persons who have left: not migrated.
- The old `logs` table of the SQLite.

## Validation

1. Run `sql/create_shiny_accounts.sql` in DBeaver; the four tables exist in `config`.
2. Export with `sql/export_shiny_credentials_sqlite.sql`, paste into
   `sql/check_shiny_accounts.sql`, run it: every account not filled has a reason in check 3a,
   checks 3b and 3c are empty or explained.
3. Run `sql/fill_shiny_accounts.sql`: account count equals the `ok` count from check 3e, and every
   row of the app-grant comparison shows `diff = 0`. Then switch `ROLLBACK` to `COMMIT`.
4. Delete the local SQLite copy.
