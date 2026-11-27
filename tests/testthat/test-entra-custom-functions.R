context("test-entra-custom-functions")

# In a session with Entra login the old helpers must not touch the SQLite
# files: the paths below do not exist, so any read would fail.
missing_db <- file.path(tempdir(), "does-not-exist.sqlite")

with_entra_session <- function(identity, code) {
  session <- list(userData = new.env())
  entra_set_session_login(session, identity)
  shiny::withReactiveDomain(session, code)
}

teamlead <- entra_identity("tim.roensch@studyflix.de", "Tim Roensch", "Teamlead", "normal")
product <- entra_identity("admin@studyflix.de", "produkt", "Entwickler", "product",
                          "Ada Admin", "admin")

test_that("permission level and role come from the Entra login", {
  with_entra_session(teamlead, {
    expect_equal(custom_permission_level(path_to_user_db = missing_db), 1)
    expect_equal(custom_retrieve_user_role_v2("Tim Roensch", path_to_user_db = missing_db),
                 "Teamlead")
    expect_equal(custom_username(), "Tim Roensch")
  })
  with_entra_session(product, {
    expect_equal(custom_permission_level(path_to_user_db = missing_db), 2)
    expect_equal(custom_retrieve_user_role_v2("produkt", path_to_user_db = missing_db),
                 "Entwickler")
  })
})

test_that("custom_access_keys_2 returns NULL for keys the Entra login does not serve", {
  with_entra_session(teamlead, {
    expect_null(custom_access_keys_2("postgresql_public_key",
                                     path_to_keys_db = missing_db,
                                     path_to_user_db = missing_db))
    expect_null(custom_access_keys("crm_public_key"))
  })
})

test_that("role names map to the same levels as before", {
  expect_equal(role_permission_level(c("Admin", "Entwickler", "Geschaeftsfuehrung",
                                       "Headof", "Verwaltung")), rep(2, 5))
  expect_equal(role_permission_level("Teamlead"), 1)
  expect_equal(role_permission_level(c("Mitarbeiter", "Head of")), c(0, 0))
})
