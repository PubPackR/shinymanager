# Dashboards log in by the Entra e-mail, with the old login window as fallback
Ticket: https://app.asana.com/0/0/1220817686363384/f (parent: https://app.asana.com/0/0/1220823360276345/f)

## Problem

Every dashboard built on `run_dashboard()` (shiny-99-modules `func/app-templates/dashboard_template.R`)
wraps itself in `secure_app()` and asks for a password, although the Entra oauth2-proxy in front of
the server already knows who the person is. The password also unlocks the keys: every
`shinymanager::custom_access_keys_2()` call reads `keys_database.sqlite` with the login password,
even under the gsm backend, because Billomatics evaluates the argument before it ignores it.
Accounts, roles and app access already live in `config` (T2, T4).

## Solution

- **Login order** in `run_dashboard(login = "auto")`, the new default:
  1. Server: `X-Forwarded-Email` in `ui(req)` and an active account in `config.shiny_accounts`
     with app access (or on the product/admin list) → logged in, no window.
  2. Laptop: no header, `interactive()` is TRUE → e-mail from `gcloud config get-value account`,
     same account check → logged in, no window. `interactive()` is FALSE on the server, so this
     path never exists there.
  3. Otherwise the old SQLite login window, unchanged (login fallback).
  `login = "sqlite"` keeps today's behaviour for an app that wants only the old window.
- **Header to server:** `ui(req)` stores the e-mail under a random token (at least 128 bit),
  valid once and for a short time; the server redeems it at session start (decision from the
  analysis, ticket body). The header itself cannot be spoofed past the proxy (tested 23.11.2026).
- **`res_auth` from config:** `user` = Personio full name, `permission` = `role_name`, plus `email`
  and `mode`. Existing level patterns keep working: `filter(salesperson == user_name)` and
  `Team == user_name`; all four Teamlead accounts have a team of the same name (checked
  27.11.2026). A test pins the four full names against `raw.personio_persons`.
- **Keys:** `custom_access_keys_2()` gets a gsm mode: `billomat_db_key` and
  `passwort_bonus_report_xlsx` come from Secret Manager, every other key returns `NULL` without
  touching `keys_database.sqlite` or `key()`.
- **Product list and admin list:** secret `studyflix-shiny-admin-list`, JSON
  `{"admin": [...], "product": [...]}`, maintained by hand. Admin includes product. People on a
  list start in product mode (`user = "produkt"`, `permission = "Entwickler"`, so the existing
  hard-coded bypasses keep working) and can pick "als Person ansehen": `user` and `permission`
  of the target, one row in `config.shiny_impersonation_log`, no further login.
- **Login log:** one row in `config.shiny_login_log` (email, app_name) per login through header
  or gcloud.
- **Display:** bottom right "angemeldet als <E-Mail> · Modus: Produkt / Normal / als <Name>".
- **Start page:** people on a list see every listed dashboard (shiny-00-start-page).

## Decisions

Earlier decisions this builds on: Q1 login by Entra e-mail without password; Q10 app access as a
table in `config`; Q11 product and admin list as a Secret Manager secret; Q14 every impersonation
is logged; Q15 `personio_person_id` on the account (analysis and T2); decision 26.11.2026: people
on the admin or product list see all dashboards without own app access rows.

- **Q51 Keys without SQLite:** (a) central gsm mode in `custom_access_keys_2`, GSM secrets for
  `billomat_db_key` and `passwort_bonus_report_xlsx`, `NULL` otherwise.
- **Q52 Contents of `res_auth`:** `user` = Personio full name, `permission` = `role_name`, plus
  `email` and `mode`.
- **Q53 Product mode and impersonation:** product mode is `user = "produkt"`,
  `permission = "Entwickler"`; impersonation takes the target's user and role; logged in
  `config.shiny_impersonation_log`.
- **Q54 Scope:** shinymanager, template, keys, GSM admin list, login log, display, start page
  admin view; the six apps with their own `secure_app` stay with T5; 5 SP; three PRs.
- **Q55 Pilot:** shiny-25.
- **Q56 Secret:** `studyflix-shiny-admin-list` as JSON `{"admin":[...],"product":[...]}`.
- **Q57 Display:** "angemeldet als <email> · Modus: Produkt / Normal / als <Name>".
- **Q58 New default for `run_dashboard()` (replaces Q50):** `login = "auto"` with the order header
  → gcloud (local, interactive) → old SQLite window; `login = "sqlite"` stays as a parameter;
  every app gets "auto" with its next redeploy, tested first with the pilot on `_test`.
- **Q59 Fallback instead of rejection until T5:** without header or account the dashboard shows
  the old login window; rejection comes with T5.

## Affected

- `packages/shinymanager`: `R/custom_functions.R` (`custom_access_keys_2`), new login helpers
  (identity, account lookup, admin list, logs), tests, this spec, `CONTEXT.md`.
- `shiny-apps/shiny-99-modules`: `func/app-templates/dashboard_template.R` (`run_dashboard`,
  `secure_app`/`secure_server` wiring, `setup_database_connection`).
- `shiny-apps/shiny-00-start-page`: `func/start_page_functions.R` (list members see all listed
  dashboards).
- Read: `config.shiny_accounts`, `config.shiny_app_access`, `config.shiny_apps`,
  `raw.personio_persons`; written: `config.shiny_login_log`, `config.shiny_impersonation_log`.
- New Secret Manager secret `studyflix-shiny-admin-list` (created by hand).
- Pilot redeploy: shiny-25 `_test`.

## Out of scope

- The six apps with their own `secure_app` (shiny-06, 21, 26, 29, 31, shiny-99 `app.R`): T5.
- Rejecting people without header or account, deleting the SQLite files: T5.
- Inventory of the remaining `keys_database` entries and dropping `encrypted_master_key` (Esta).
- Replacing the hard-coded `"produkt"` / `"admin"` bypasses in the modules.

## Validation

1. Locally in Positron, signed in to gcloud: shiny-25 opens without a window, bottom right shows
   your e-mail and "Modus: Produkt"; "als Person ansehen" with a salesperson shows that person's
   data and writes one row to `config.shiny_impersonation_log`.
2. shiny-25 `_test` on the server: opens without a window, one row in `config.shiny_login_log`.
3. An e-mail without account (deactivate it in shiny-21): the old login window appears and works
   with the SQLite password.
4. The Billomat figures in shiny-25 load (key from Secret Manager).
5. shiny-00-start-page shows all listed dashboards for a person on the admin list.
