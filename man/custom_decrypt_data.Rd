% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/custom_functions.R
\name{custom_decrypt_data}
\alias{custom_decrypt_data}
\title{custom_decrypt_data}
\usage{
custom_decrypt_data(decryption_key, encrypted_df)
}
\arguments{
\item{decryption_key}{the secret to decrypt the data with}

\item{encrypted_df}{encrypted data frames}
}
\description{
Decrypts a dataframe with the decrypted content. 
The decryption key has to be passed down within a function.
Function is deprecated, please use custom_decrypt_data_2.
}
