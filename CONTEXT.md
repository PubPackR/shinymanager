# shinymanager — domain glossary

## Account
A personal login to the Shiny dashboards, belonging to exactly one Personio person and keyed by
that person's Entra e-mail. There is no password: on the server the identity comes from the Entra login in
front of it, on a laptop from the person's Google login. Shared or team logins are not accounts.

## Display name
The name an account appears as inside a dashboard: the person's full name in Personio. Team views
match it against the team name.

## Role
What an account may see inside a dashboard, expressed as a permission level: 0 own data, 1 team
data, 2 all data.

## App access
The permission for an account to open one dashboard. A dashboard's `_test` instance is a
separate dashboard with its own app access.

## Product mode
The default mode of a person on the product whitelist: they see the dashboards as the shared
"produkt" view instead of as themselves.

## Impersonation
A person on the product whitelist viewing a dashboard as another account, e.g. to reproduce what
a salesperson sees. Every impersonation is logged.

## Admin
A person on the admin list. Admins include product mode and may open the account management app.

## Product list and admin list
The two hand-maintained lists of e-mails that grant product mode and admin rights. They live
outside the account tables, and dashboards only read them. People on either list see every
dashboard without app access of their own.

## Login fallback
The old password login window. Until the old user file is retired, a person without an account,
or without an Entra or Google identity, sees it instead of being turned away.

## Login log
One entry per sign-in through the Entra or Google identity: who, which dashboard, which mode.
