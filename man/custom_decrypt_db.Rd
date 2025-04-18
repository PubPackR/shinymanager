% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/custom_functions.R
\name{custom_decrypt_db}
\alias{custom_decrypt_db}
\title{custom_decrypt_db}
\usage{
custom_decrypt_db(
  df,
  name_of_secret,
  columns_to_decrypt,
  base_app = FALSE,
  key = NULL,
  path_to_keys_db = "../../base-data/database/keys_database.sqlite",
  path_to_user_db = "../../base-data/database/shiny_users.sqlite"
)
}
\arguments{
\item{df}{The dataframe to be decrypted.}

\item{name_of_secret}{The name of the secret that decrypts the data.}

\item{columns_to_decrypt}{The columns that need to be decrpyted.}

\item{base_app}{Boolean indicating if this function is used in a base_app (Optional).}

\item{key}{The key (Optional).}

\item{path_to_keys_db}{Path to keys_database.sqlite (optional).}

\item{path_to_user_db}{Path to shiny_users.sqlite (optional).}
}
\value{
The specified columns of the database table gets decrypted
}
\description{
This function is used to decrypt a dataframe that is saved within a sqlite database.
You are able to specifiy which columns you want to decrypt.
}
