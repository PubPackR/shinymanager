# shinymanager — domain glossary

## Account
A personal login to the Shiny dashboards, belonging to exactly one Personio person and keyed by
that person's Entra e-mail. There is no password: the identity comes from the Entra login in
front of the server. Shared or team logins are not accounts.

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
