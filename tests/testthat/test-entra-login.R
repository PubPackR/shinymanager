context("test-entra-login")

# Fake session: only userData is used.
fake_session <- function() list(userData = new.env())

lists <- list(admin = "admin@studyflix.de",
              product = c("admin@studyflix.de", "product@studyflix.de"))

account_row <- function(email, full_name, role_name, has_app_access = TRUE) {
  data.frame(email = email, full_name = full_name, role_name = role_name,
             has_app_access = has_app_access, stringsAsFactors = FALSE)
}
no_account <- account_row(character(0), character(0), character(0), logical(0))

resolve <- function(rows, email) {
  entra_resolve_identity(NULL, email, "shiny-25", lists,
                         find_account = function(con, email, app_name) {
                           rows[rows$email == email, , drop = FALSE]
                         })
}


# ----- E-mail of the viewer ---------------------------------------------------

test_that("the header wins and is normalised", {
  req <- list(HTTP_X_FORWARDED_EMAIL = "  Tim.Roensch@Studyflix.de ")
  expect_equal(entra_viewer_email(req, is_local = TRUE,
                                  gcloud_account = function() "other@studyflix.de"),
               "tim.roensch@studyflix.de")
})

test_that("without header the server never falls back to gcloud", {
  expect_equal(entra_viewer_email(list(), is_local = FALSE,
                                  gcloud_account = function() "me@studyflix.de"), "")
})

test_that("on a laptop the gcloud account is used", {
  expect_equal(entra_viewer_email(list(), is_local = TRUE,
                                  gcloud_account = function() "Me@studyflix.de"),
               "me@studyflix.de")
  expect_equal(entra_viewer_email(list(), is_local = TRUE,
                                  gcloud_account = function() ""), "")
})


# ----- Lists ------------------------------------------------------------------

test_that("admin includes product, case does not matter", {
  l <- entra_read_lists(function() '{"admin": ["A@studyflix.de"], "product": ["p@studyflix.de"]}')
  expect_equal(l$admin, "a@studyflix.de")
  expect_setequal(l$product, c("a@studyflix.de", "p@studyflix.de"))
  expect_equal(entra_list_role("a@studyflix.de", l), "admin")
  expect_equal(entra_list_role("p@studyflix.de", l), "product")
  expect_true(is.na(entra_list_role("x@studyflix.de", l)))
})

test_that("an unreadable or invalid secret fails closed without its content", {
  expect_warning(l <- entra_read_lists(function() stop("access denied")), "access denied")
  expect_length(l$product, 0)
  expect_warning(l <- entra_read_lists(function() "{not json: [secret-value"), "not valid JSON")
  expect_length(l$admin, 0)
})


# ----- Identity ---------------------------------------------------------------

rows <- rbind(
  account_row("tim.roensch@studyflix.de", "Tim Roensch", "Teamlead"),
  account_row("no.access@studyflix.de", "No Access", "Mitarbeiter", FALSE),
  account_row("admin@studyflix.de", "Ada Admin", "Admin")
)

test_that("an account with app access logs in as itself", {
  id <- resolve(rows, "tim.roensch@studyflix.de")
  expect_equal(id$user, "Tim Roensch")
  expect_equal(id$permission, "Teamlead")
  expect_equal(id$mode, "normal")
})

test_that("no account or no app access means fallback (NULL)", {
  expect_null(resolve(rows, "unknown@studyflix.de"))
  expect_null(resolve(rows, "no.access@studyflix.de"))
  expect_null(resolve(rows, ""))
})

test_that("list members start in product mode, with or without account", {
  id <- resolve(rows, "admin@studyflix.de")
  expect_equal(id$user, "produkt")
  expect_equal(id$permission, "Entwickler")
  expect_equal(id$mode, "product")
  expect_equal(id$display_name, "Ada Admin")
  expect_equal(id$list_role, "admin")

  id <- resolve(rows, "product@studyflix.de")
  expect_equal(id$mode, "product")
  expect_equal(id$display_name, "product@studyflix.de")
})

test_that("impersonation takes user and role of the target and keeps the actor", {
  actor <- entra_identity("admin@studyflix.de", "produkt", "Entwickler", "product",
                          "Ada Admin", "admin")
  target <- account_row("tim.roensch@studyflix.de", "Tim Roensch", "Teamlead")
  id <- entra_impersonate(actor, target)
  expect_equal(id$user, "Tim Roensch")
  expect_equal(id$permission, "Teamlead")
  expect_equal(id$email, "admin@studyflix.de")
  expect_equal(entra_status_text(id),
               "angemeldet als admin@studyflix.de · Modus: als Tim Roensch")

  normal <- entra_identity("tim.roensch@studyflix.de", "Tim Roensch", "Teamlead", "normal")
  expect_error(entra_impersonate(normal, target), "product or admin list")
  expect_equal(entra_status_text(normal),
               "angemeldet als tim.roensch@studyflix.de · Modus: Normal")
})


# ----- Tokens -----------------------------------------------------------------

test_that("a token is valid once", {
  id <- entra_identity("a@studyflix.de", "A", "Mitarbeiter", "normal")
  tok <- entra_issue_token(id)
  expect_match(tok, "^[0-9a-f]{64}$")
  expect_equal(entra_redeem_token(tok), id)
  expect_null(entra_redeem_token(tok))
})

test_that("expired, unknown and malformed tokens are refused", {
  tok <- entra_issue_token(entra_identity("a@studyflix.de", "A", "M", "normal"),
                           ttl_seconds = -1)
  expect_null(entra_redeem_token(tok))
  expect_null(entra_redeem_token(strrep("a", 64)))
  expect_null(entra_redeem_token("../etc"))
  expect_null(entra_redeem_token(NULL))
})

test_that("a view-as request only works for the person who asked, once", {
  tok <- entra_issue_view_as("admin@studyflix.de", "tim.roensch@studyflix.de")
  expect_null(entra_redeem_view_as(tok, "someone.else@studyflix.de"))
  # the failed attempt consumed it
  expect_null(entra_redeem_view_as(tok, "admin@studyflix.de"))

  tok <- entra_issue_view_as("admin@studyflix.de", "tim.roensch@studyflix.de")
  expect_equal(entra_redeem_view_as(tok, "admin@studyflix.de"), "tim.roensch@studyflix.de")
})


# ----- Session ----------------------------------------------------------------

test_that("user_name() and key() prefer the Entra login of the session", {
  session <- fake_session()
  .entra_state$legacy_user_name <- function() "password user"
  .entra_state$legacy_key <- function() "password"
  on.exit({
    .entra_state$legacy_user_name <- NULL
    .entra_state$legacy_key <- NULL
  })

  # outside a session: the last password login, as before
  expect_equal(user_name(), "password user")
  expect_equal(key(), "password")

  # a password session gets its own login, not the last one of the process
  own <- fake_session()
  own$userData$shinymanager_legacy_user_name <- function() "own user"
  own$userData$shinymanager_legacy_key <- function() "own password"
  shiny::withReactiveDomain(own, {
    expect_equal(user_name(), "own user")
    expect_equal(key(), "own password")
  })

  entra_set_session_login(session, entra_identity("a@studyflix.de", "Anna A", "Teamlead", "normal"))
  shiny::withReactiveDomain(session, {
    expect_equal(user_name(), "Anna A")
    expect_null(key())
  })
})

test_that("keys of an Entra session come from Secret Manager or are NULL", {
  fetch <- function(name) paste("value of", name)
  expect_equal(entra_access_key("billomat_db_key", fetch),
               "value of studyflix-legacy-data-key-billomat")
  expect_equal(entra_access_key("passwort_bonus_report_xlsx", fetch),
               "value of studyflix-shiny-bonus-report-xlsx-password")
  expect_null(entra_access_key("postgresql_public_key", fetch))
})
