% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/custom_functions.R
\name{custom_add_user}
\alias{custom_add_user}
\title{custom_add_user}
\usage{
custom_add_user(
  include_master_key = TRUE,
  path_to_user_db = "../../base-data/database/shiny_users.sqlite"
)
}
\arguments{
\item{include_master_key}{Boolean indicating if the master key should be accessible to the user (optional).}

\item{path_to_user_db}{Path to shiny_users.sqlite (optional).}
}
\value{
A message indicating success or the specific error encountered.
}
\description{
Adds a user on your local device, who has access to sensible data.
}
