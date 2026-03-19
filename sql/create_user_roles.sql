-- TABLE: public.user_roles
-- Single source of truth for role -> permission level mapping.
-- perm_level: 0 = regular, 1 = teamlead, 2 = privileged (full scope via placeholder)
--
-- SQL functions (e.g. get_service_users_in_scope) and R helpers
-- (custom_get_privileged_roles, custom_get_permission_level) read from this table.
-- The hardcoded fallback list in R's determine_permission_level() must stay in sync.

CREATE TABLE IF NOT EXISTS public.user_roles (
    role_name  TEXT    NOT NULL PRIMARY KEY,
    perm_level INTEGER NOT NULL
);

INSERT INTO public.user_roles (role_name, perm_level) VALUES
    ('Admin',              2),
    ('Entwickler',         2),
    ('Geschaeftsfuehrung', 2),
    ('Headof',             2),
    ('Verwaltung',         2),
    ('Teamlead',           1)
ON CONFLICT DO NOTHING;
