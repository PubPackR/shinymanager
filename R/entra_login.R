# Entra login
#
# A dashboard learns who is looking at it without a password: on the server
# from the X-Forwarded-Email header that oauth2-proxy sets after the Entra
# login, on a laptop from the gcloud account. Accounts, roles and app access
# come from config (T2); the product list and the admin list come from the
# Secret Manager secret studyflix-shiny-admin-list. Whoever has no account
# falls back to the old password login. Spec:
# docs/specs/2026-11-27-entra-login.md.
#
# The header arrives only in ui(req), not in session$request, so ui(req)
# resolves the identity and hands it to the server through a random one-time
# token (entra_issue_token / entra_redeem_token).
#
# Once a session is logged in, its identity lives in session$userData. The
# helpers that used to read the password login (user_name(), key(),
# custom_permission_level(), custom_retrieve_user_role_v2(),
# custom_access_keys_2()) read it from there first.


# ----- State ------------------------------------------------------------------

# Per R process. ui(req) and the server of a dashboard run in the same process,
# so a token issued in ui(req) can be redeemed by the session it belongs to.
.entra_state <- new.env(parent = emptyenv())
.entra_state$tokens <- list()
.entra_state$view_as <- list()
# Last password login of this process, kept for apps that still use the old
# login only. This is what the former global closures `user_name <<-` and
# `key <<-` held.
.entra_state$legacy_user_name <- NULL
.entra_state$legacy_key <- NULL

entra_admin_list_secret <- "studyflix-shiny-admin-list"

# Keys a logged-in session may still need, mapped to their Secret Manager
# names (spec, Q51 and Q61-Q62). Every other key of keys_database resolves to
# NULL under the Entra login.
entra_gsm_keys <- c(
  billomat_db_key = "studyflix-legacy-data-key-billomat",
  passwort_bonus_report_xlsx = "studyflix-shiny-bonus-report-xlsx-password"
)

entra_session_key <- "shinymanager_entra_login"


# ----- E-mail of the viewer ---------------------------------------------------

#' Normalise e-mail addresses
#'
#' Lower case without surrounding blanks, so an address matches whatever case
#' Entra, gcloud or the account table use.
#'
#' @param x Character vector, NULL or NA.
#' @return Character vector of the same length (empty strings for missing
#'   values); `character(0)` for NULL.
#' @export
entra_normalise_email <- function(x) {
  # ---- start ---- #
  if (is.null(x) || length(x) == 0) return(character(0))
  x <- as.character(x)
  x[is.na(x)] <- ""
  tolower(trimws(x))
}


#' E-mail of the gcloud account on this machine
#'
#' @return The account of `gcloud config get-value account`, or `""` when
#'   gcloud is missing or nobody is logged in.
#' @export
entra_gcloud_account <- function() {
  # ---- start ---- #
  out <- tryCatch(
    suppressWarnings(system2("gcloud", c("config", "get-value", "account"),
                             stdout = TRUE, stderr = FALSE)),
    error = function(e) character(0)
  )
  out <- entra_normalise_email(out)
  out <- out[grepl("@", out, fixed = TRUE)]
  if (length(out) == 0) "" else out[1]
}


#' E-mail of the person looking at the dashboard
#'
#' Order: the oauth2-proxy header; only when R runs interactively (a laptop)
#' the gcloud account. `interactive()` is FALSE on the Shiny server, so there a
#' missing header always yields `""`.
#'
#' @param req The request passed to `ui(req)`.
#' @param is_local TRUE when the app runs on a laptop. Defaults to `interactive()`.
#' @param gcloud_account Function returning the gcloud account. Injected in tests.
#' @return Normalised e-mail or `""`.
#' @export
entra_viewer_email <- function(req, is_local = interactive(),
                               gcloud_account = entra_gcloud_account) {
  # ---- start ---- #
  header <- entra_normalise_email(req$HTTP_X_FORWARDED_EMAIL)
  if (length(header) == 1 && nzchar(header)) return(header)
  if (!isTRUE(is_local)) return("")
  local <- entra_normalise_email(gcloud_account())
  if (length(local) == 1 && grepl("@", local, fixed = TRUE)) local else ""
}


# ----- Product list and admin list --------------------------------------------

#' Read the product list and the admin list
#'
#' The secret is JSON: `{"admin": [...], "product": [...]}`. Admin includes
#' product. Fails closed: if the secret cannot be read or parsed, both lists
#' are empty and a warning names the reason, never the content.
#'
#' @param fetch Function returning the secret as a string. Injected in tests.
#' @return List with character vectors `admin` and `product` (normalised).
#' @export
entra_read_lists <- function(fetch = function() secretsR::secret_get(entra_admin_list_secret)) {
  # ---- start ---- #
  empty <- list(admin = character(0), product = character(0))

  raw <- tryCatch(fetch(), error = function(e) {
    warning("Admin list could not be read, nobody gets product mode: ",
            conditionMessage(e), call. = FALSE)
    NULL
  })
  if (is.null(raw)) return(empty)

  parsed <- tryCatch(yaml::yaml.load(raw), error = function(e) NULL)
  if (!is.list(parsed)) {
    warning("Admin list is not valid JSON, nobody gets product mode.", call. = FALSE)
    return(empty)
  }

  admin <- entra_normalise_email(unlist(parsed$admin))
  product <- entra_normalise_email(unlist(parsed$product))
  admin <- unique(admin[nzchar(admin)])
  product <- unique(c(admin, product[nzchar(product)]))
  list(admin = admin, product = product)
}


#' Which list an e-mail is on
#'
#' @param email Normalised e-mail.
#' @param lists Result of `entra_read_lists()`.
#' @return `"admin"`, `"product"` or `NA_character_`.
#' @export
entra_list_role <- function(email, lists) {
  # ---- start ---- #
  if (length(email) != 1 || !nzchar(email)) return(NA_character_)
  if (email %in% lists$admin) return("admin")
  if (email %in% lists$product) return("product")
  NA_character_
}


# ----- Accounts from config ---------------------------------------------------

#' Tables the Entra login reads
#'
#' For `needed_tables` of the pool that resolves the login.
#' @return Character vector of schema-qualified table names.
#' @export
entra_needed_tables <- function() {
  # ---- start ---- #
  c("config.shiny_accounts", "config.shiny_app_access", "raw.personio_persons",
    "config.shiny_login_log", "config.shiny_impersonation_log")
}


#' Look up the active account of an e-mail
#'
#' @param con DBI connection or pool.
#' @param email Normalised e-mail.
#' @param app_name App folder name the person opens.
#' @return Data frame with 0 or 1 rows: `email`, `full_name` (Personio first
#'   name and name), `role_name`, `has_app_access`.
#' @export
entra_find_account <- function(con, email, app_name) {
  # ---- start ---- #
  DBI::dbGetQuery(con, "
    SELECT a.email,
           trim(concat(p.first_name, ' ', p.name)) AS full_name,
           a.role_name,
           EXISTS (
             SELECT 1 FROM config.shiny_app_access x
             WHERE x.account_id = a.id AND x.app_name = $2
           ) AS has_app_access
    FROM config.shiny_accounts a
    JOIN raw.personio_persons p ON p.id = a.personio_person_id
    WHERE lower(trim(a.email)) = $1
      AND a.is_active",
    params = list(email, app_name))
}


#' Active accounts a list member can view the dashboard as
#'
#' @param con DBI connection or pool.
#' @return Data frame `email`, `full_name`, `role_name`, sorted by name.
#' @export
entra_list_accounts <- function(con) {
  # ---- start ---- #
  DBI::dbGetQuery(con, "
    SELECT lower(trim(a.email)) AS email,
           trim(concat(p.first_name, ' ', p.name)) AS full_name,
           a.role_name
    FROM config.shiny_accounts a
    JOIN raw.personio_persons p ON p.id = a.personio_person_id
    WHERE a.is_active
    ORDER BY lower(trim(concat(p.first_name, ' ', p.name)))")
}


# ----- Identity ---------------------------------------------------------------

#' Build an identity
#'
#' The identity is what a logged-in session knows about its viewer. `user` and
#' `permission` are what the dashboards read as `res_auth$user` and
#' `res_auth$permission`; `email`, `display_name` and `list_role` always belong
#' to the person who logged in, also while they view as someone else.
#'
#' @param email E-mail of the person who logged in.
#' @param user Name the dashboard filters by.
#' @param permission Role name.
#' @param mode `"normal"`, `"product"` or `"impersonation"`.
#' @param display_name Own name of the person who logged in.
#' @param list_role `"admin"`, `"product"` or NA.
#' @param viewed_as_email,viewed_as_name Target of an impersonation, else NA.
#' @return Named list.
#' @export
entra_identity <- function(email, user, permission, mode, display_name = email,
                           list_role = NA_character_,
                           viewed_as_email = NA_character_,
                           viewed_as_name = NA_character_) {
  # ---- start ---- #
  list(email = email, user = user, permission = permission, mode = mode,
       display_name = display_name, list_role = list_role,
       viewed_as_email = viewed_as_email, viewed_as_name = viewed_as_name)
}


#' Resolve the identity of a viewer
#'
#' A person on the product or admin list starts in product mode, with or
#' without an account (spec, Q53). Everybody else needs an active account with
#' app access to `app_name`. Returns NULL otherwise: the dashboard then shows
#' the old login window (Q59).
#'
#' @param con DBI connection or pool.
#' @param email Normalised e-mail, `""` if unknown.
#' @param app_name App folder name.
#' @param lists Result of `entra_read_lists()`.
#' @param find_account Account lookup, `entra_find_account()`. Injected in tests.
#' @return Identity (see `entra_identity()`) or NULL.
#' @export
entra_resolve_identity <- function(con, email, app_name, lists,
                                   find_account = entra_find_account) {
  # ---- start ---- #
  if (length(email) != 1 || !nzchar(email)) return(NULL)

  account <- find_account(con, email, app_name)
  own_name <- if (nrow(account) > 0) account$full_name[1] else email
  list_role <- entra_list_role(email, lists)

  if (!is.na(list_role)) {
    return(entra_identity(email, user = "produkt", permission = "Entwickler",
                          mode = "product", display_name = own_name,
                          list_role = list_role))
  }
  if (nrow(account) == 0 || !isTRUE(as.logical(account$has_app_access[1]))) {
    return(NULL)
  }
  entra_identity(email, user = account$full_name[1],
                 permission = account$role_name[1], mode = "normal",
                 display_name = own_name)
}


#' View the dashboard as another account
#'
#' Takes over `user` and `permission` of the target; the person who logged in
#' stays in `email`, `display_name` and `list_role`. Only for list members.
#'
#' @param identity Identity of a list member (product mode).
#' @param target One row of `entra_list_accounts()`.
#' @return Identity in mode `"impersonation"`.
#' @export
entra_impersonate <- function(identity, target) {
  # ---- start ---- #
  if (is.na(identity$list_role)) {
    stop("Only people on the product or admin list may view as another person.",
         call. = FALSE)
  }
  identity$user <- target$full_name[1]
  identity$permission <- target$role_name[1]
  identity$mode <- "impersonation"
  identity$viewed_as_email <- target$email[1]
  identity$viewed_as_name <- target$full_name[1]
  identity
}


#' Text of the login display
#'
#' @param identity Identity of the session.
#' @return For example "angemeldet als a@b.de · Modus: Produkt".
#' @export
entra_status_text <- function(identity) {
  # ---- start ---- #
  mode <- switch(identity$mode,
    product = "Produkt",
    impersonation = paste("als", identity$viewed_as_name),
    "Normal"
  )
  paste0("angemeldet als ", identity$email, " · Modus: ", mode)
}


# ----- Tokens -----------------------------------------------------------------

entra_new_token <- function() {
  # ---- start ---- #
  paste(as.character(openssl::rand_bytes(32)), collapse = "")
}

entra_prune <- function(store) {
  # ---- start ---- #
  now <- Sys.time()
  Filter(function(entry) entry$expires > now, store)
}


#' Hand an identity from ui(req) to the server
#'
#' The token is random (256 bit), valid once and for `ttl_seconds`.
#'
#' @param identity Identity from `entra_resolve_identity()`.
#' @param ttl_seconds Lifetime in seconds.
#' @return Token as hex string.
#' @export
entra_issue_token <- function(identity, ttl_seconds = 120) {
  # ---- start ---- #
  token <- entra_new_token()
  tokens <- entra_prune(.entra_state$tokens)
  tokens[[token]] <- list(identity = identity, expires = Sys.time() + ttl_seconds)
  .entra_state$tokens <- tokens
  token
}


#' Redeem a token issued by `entra_issue_token()`
#'
#' @param token Token string.
#' @return The identity, or NULL if the token is unknown, used or expired.
#' @export
entra_redeem_token <- function(token) {
  # ---- start ---- #
  entra_redeem(token, "tokens")$identity
}


#' Request to view as another account
#'
#' Issued by the server of a list member, redeemed by `ui(req)` after the page
#' reloads with `?entra_view_as=<token>`. Valid once and for `ttl_seconds`.
#'
#' @param actor_email E-mail of the list member.
#' @param target_email E-mail of the account to view as.
#' @param ttl_seconds Lifetime in seconds.
#' @return Token as hex string.
#' @export
entra_issue_view_as <- function(actor_email, target_email, ttl_seconds = 60) {
  # ---- start ---- #
  token <- entra_new_token()
  store <- entra_prune(.entra_state$view_as)
  store[[token]] <- list(actor_email = actor_email, target_email = target_email,
                         expires = Sys.time() + ttl_seconds)
  .entra_state$view_as <- store
  token
}


#' Redeem a view-as request
#'
#' @param token Token string from the query string.
#' @param actor_email E-mail of the person loading the page; must match the
#'   person who asked, so a forwarded link is worthless.
#' @return E-mail of the target, or NULL.
#' @export
entra_redeem_view_as <- function(token, actor_email) {
  # ---- start ---- #
  entry <- entra_redeem(token, "view_as")
  if (is.null(entry) || !identical(entry$actor_email, actor_email)) return(NULL)
  entry$target_email
}


entra_redeem <- function(token, store_name) {
  # ---- start ---- #
  if (!is.character(token) || length(token) != 1 ||
      !grepl("^[0-9a-f]{64}$", token)) {
    return(NULL)
  }
  store <- .entra_state[[store_name]]
  entry <- store[[token]]
  store[[token]] <- NULL
  .entra_state[[store_name]] <- store
  if (is.null(entry) || entry$expires <= Sys.time()) return(NULL)
  entry
}


# ----- Session ----------------------------------------------------------------

#' Store the identity of a logged-in session
#'
#' @param session Shiny session.
#' @param identity Identity.
#' @return The identity, invisibly.
#' @export
entra_set_session_login <- function(session, identity) {
  # ---- start ---- #
  session$userData[[entra_session_key]] <- identity
  invisible(identity)
}


#' Identity of the current session
#'
#' @param session Shiny session; defaults to the current reactive domain.
#' @return The identity, or NULL outside a session or without Entra login.
#' @export
entra_session_login <- function(session = shiny::getDefaultReactiveDomain()) {
  # ---- start ---- #
  if (is.null(session)) return(NULL)
  session$userData[[entra_session_key]]
}


#' Name of the logged-in user
#'
#' Replaces the global closure that the password login used to assign. In a
#' session with Entra login it returns that session's user; otherwise the user
#' of the last password login in this process, as before.
#'
#' @return Character scalar or NULL.
#' @export
user_name <- function() {
  # ---- start ---- #
  login <- entra_session_login()
  if (!is.null(login)) return(login$user)
  fn <- .entra_state$legacy_user_name
  if (is.null(fn)) NULL else fn()
}


#' Password of the logged-in user
#'
#' Replaces the global closure that the password login used to assign. A
#' session with Entra login has no password and gets NULL; otherwise the
#' password of the last password login in this process, as before.
#'
#' @return Character scalar or NULL.
#' @export
key <- function() {
  # ---- start ---- #
  if (!is.null(entra_session_login())) return(NULL)
  fn <- .entra_state$legacy_key
  if (is.null(fn)) NULL else fn()
}


# ----- Keys -------------------------------------------------------------------

#' Key for a session with Entra login
#'
#' @param name_of_secret Name in keys_database.
#' @param fetch Function reading a Secret Manager secret. Injected in tests.
#' @return The secret, or NULL for keys the Entra login does not serve.
#' @export
entra_access_key <- function(name_of_secret,
                             fetch = function(name) secretsR::secret_get(name)) {
  # ---- start ---- #
  if (!name_of_secret %in% names(entra_gsm_keys)) return(NULL)
  fetch(entra_gsm_keys[[name_of_secret]])
}


# ----- Logs -------------------------------------------------------------------

#' Write the login and, if any, the impersonation to the logs
#'
#' @param con DBI connection or pool.
#' @param identity Identity of the session.
#' @param app_name App folder name.
#' @return Invisible NULL.
#' @export
entra_log_session <- function(con, identity, app_name) {
  # ---- start ---- #
  DBI::dbExecute(con,
    "INSERT INTO config.shiny_login_log (email, app_name) VALUES ($1, $2)",
    params = list(identity$email, app_name))
  if (identical(identity$mode, "impersonation")) {
    DBI::dbExecute(con,
      "INSERT INTO config.shiny_impersonation_log (actor_email, target_email, app_name)
       VALUES ($1, $2, $3)",
      params = list(identity$email, identity$viewed_as_email, app_name))
  }
  invisible(NULL)
}
