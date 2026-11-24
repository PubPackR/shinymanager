-- TABLES: config.shiny_accounts, config.shiny_app_access,
--         config.shiny_impersonation_log, config.shiny_login_log
--
-- Dashboard accounts, app access and the two audit logs, replacing the
-- credentials and logs tables in base-data/database/shiny_users.sqlite.
-- An account is keyed by the Entra e-mail that oauth2-proxy forwards as
-- X-Forwarded-Email; there is no password.
--
-- The product whitelist and the admin list are NOT stored here: they live as a
-- secret in Google Secret Manager, maintained by hand only.
--
-- DEPLOY ORDER: config.shiny_user_roles (create_user_roles.sql) must exist first.
-- Filling: fill_shiny_accounts.sql, after check_shiny_accounts.sql.


-- ---------------------------------------------------------------------------
-- config.shiny_accounts
-- ---------------------------------------------------------------------------

CREATE TABLE config.shiny_accounts (
    id bigint NOT NULL GENERATED ALWAYS AS IDENTITY ( INCREMENT 1 START 1 MINVALUE 1 MAXVALUE 9223372036854775807 CACHE 1 ),
    created_at timestamp without time zone NOT NULL DEFAULT now(),
    updated_at timestamp without time zone NOT NULL DEFAULT now(),

    email text NOT NULL,
    personio_person_id bigint NOT NULL,
    role_name text NOT NULL,
    is_active boolean NOT NULL DEFAULT true,

    CONSTRAINT pk_shiny_accounts PRIMARY KEY (id),
    CONSTRAINT fk_shiny_accounts_personio_persons FOREIGN KEY (personio_person_id)
        REFERENCES raw.personio_persons (id) ON DELETE CASCADE,
    CONSTRAINT fk_shiny_accounts_shiny_user_roles FOREIGN KEY (role_name)
        REFERENCES config.shiny_user_roles (role_name) ON DELETE CASCADE,
    CONSTRAINT uq_shiny_accounts_email UNIQUE (email)
);

CREATE INDEX idx_shiny_accounts_personio_person_id ON config.shiny_accounts (personio_person_id);
CREATE INDEX idx_shiny_accounts_role_name ON config.shiny_accounts (role_name);

COMMENT ON TABLE config.shiny_accounts IS 'One personal account per person for the Shiny dashboards. Identity comes from the Entra login (oauth2-proxy), not from a password. Shared or team accounts do not exist here.';
COMMENT ON COLUMN config.shiny_accounts.email IS 'Entra e-mail address as forwarded by oauth2-proxy in X-Forwarded-Email; the login key of the account.';
COMMENT ON COLUMN config.shiny_accounts.personio_person_id IS 'Personio person this account belongs to; drives the name-based scope of the dashboards.';
COMMENT ON COLUMN config.shiny_accounts.role_name IS 'Dashboard role; its permission level comes from config.shiny_user_roles.';
COMMENT ON COLUMN config.shiny_accounts.is_active IS 'FALSE blocks the login without deleting the account and its app access.';

CREATE OR REPLACE TRIGGER trigger_set_updated_at
    BEFORE UPDATE
    ON config.shiny_accounts
    FOR EACH ROW
    EXECUTE FUNCTION public.update_timestamp();


-- ---------------------------------------------------------------------------
-- config.shiny_app_access
-- ---------------------------------------------------------------------------

CREATE TABLE config.shiny_app_access (
    id bigint NOT NULL GENERATED ALWAYS AS IDENTITY ( INCREMENT 1 START 1 MINVALUE 1 MAXVALUE 9223372036854775807 CACHE 1 ),
    created_at timestamp without time zone NOT NULL DEFAULT now(),
    updated_at timestamp without time zone NOT NULL DEFAULT now(),

    account_id bigint NOT NULL,
    app_name text NOT NULL,

    CONSTRAINT pk_shiny_app_access PRIMARY KEY (id),
    CONSTRAINT fk_shiny_app_access_shiny_accounts FOREIGN KEY (account_id)
        REFERENCES config.shiny_accounts (id) ON DELETE CASCADE,
    CONSTRAINT uq_shiny_app_access_account_id_app_name UNIQUE (account_id, app_name)
);

CREATE INDEX idx_shiny_app_access_account_id ON config.shiny_app_access (account_id);

COMMENT ON TABLE config.shiny_app_access IS 'Which account may open which dashboard. One row per account and app; the _test instance of an app is a separate row.';
COMMENT ON COLUMN config.shiny_app_access.account_id IS 'Account that is granted access.';
COMMENT ON COLUMN config.shiny_app_access.app_name IS 'App folder name on the server as returned by basename(getwd()), e.g. shiny-25-Sales_Dashboard_Provision or shiny-25-Sales_Dashboard_Provision_test.';

CREATE OR REPLACE TRIGGER trigger_set_updated_at
    BEFORE UPDATE
    ON config.shiny_app_access
    FOR EACH ROW
    EXECUTE FUNCTION public.update_timestamp();


-- ---------------------------------------------------------------------------
-- config.shiny_impersonation_log
-- ---------------------------------------------------------------------------

CREATE TABLE config.shiny_impersonation_log (
    id bigint NOT NULL GENERATED ALWAYS AS IDENTITY ( INCREMENT 1 START 1 MINVALUE 1 MAXVALUE 9223372036854775807 CACHE 1 ),
    created_at timestamp without time zone NOT NULL DEFAULT now(),
    updated_at timestamp without time zone NOT NULL DEFAULT now(),

    actor_email text NOT NULL,
    target_email text NOT NULL,
    app_name text NOT NULL,
    started_at timestamp without time zone NOT NULL DEFAULT now(),

    CONSTRAINT pk_shiny_impersonation_log PRIMARY KEY (id)
);

COMMENT ON TABLE config.shiny_impersonation_log IS 'Audit log: every time a person on the product whitelist views a dashboard as another person. Stores e-mails as text without foreign keys, so deleting an account keeps its history.';
COMMENT ON COLUMN config.shiny_impersonation_log.actor_email IS 'E-mail of the whitelisted person who switched.';
COMMENT ON COLUMN config.shiny_impersonation_log.target_email IS 'E-mail of the account that was viewed.';
COMMENT ON COLUMN config.shiny_impersonation_log.app_name IS 'App folder name the switch happened in.';
COMMENT ON COLUMN config.shiny_impersonation_log.started_at IS 'When the switch started, UTC.';

CREATE OR REPLACE TRIGGER trigger_set_updated_at
    BEFORE UPDATE
    ON config.shiny_impersonation_log
    FOR EACH ROW
    EXECUTE FUNCTION public.update_timestamp();


-- ---------------------------------------------------------------------------
-- config.shiny_login_log
-- ---------------------------------------------------------------------------

CREATE TABLE config.shiny_login_log (
    id bigint NOT NULL GENERATED ALWAYS AS IDENTITY ( INCREMENT 1 START 1 MINVALUE 1 MAXVALUE 9223372036854775807 CACHE 1 ),
    created_at timestamp without time zone NOT NULL DEFAULT now(),
    updated_at timestamp without time zone NOT NULL DEFAULT now(),

    email text NOT NULL,
    app_name text NOT NULL,
    logged_in_at timestamp without time zone NOT NULL DEFAULT now(),

    CONSTRAINT pk_shiny_login_log PRIMARY KEY (id)
);

COMMENT ON TABLE config.shiny_login_log IS 'Login history of the dashboards, one row per login. Starts empty; the old logs table of shiny_users.sqlite is not migrated. No foreign keys, so deleting an account keeps its history.';
COMMENT ON COLUMN config.shiny_login_log.email IS 'Entra e-mail of the person who logged in.';
COMMENT ON COLUMN config.shiny_login_log.app_name IS 'App folder name that was opened.';
COMMENT ON COLUMN config.shiny_login_log.logged_in_at IS 'When the login happened, UTC.';

CREATE OR REPLACE TRIGGER trigger_set_updated_at
    BEFORE UPDATE
    ON config.shiny_login_log
    FOR EACH ROW
    EXECUTE FUNCTION public.update_timestamp();
