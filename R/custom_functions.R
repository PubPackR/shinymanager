#' custom_access_keys
#'
#' Decrypts master_key using users password (entered through shinymanager ui) from the shiny_users.sqlite database
#' Afterwards decrypts requested data with the decrypted master_key from the keys_database.sqlite
#' Function is deprecated, please use custom_access_keys_2.
#'
#' @param requested_data Name of the secret you want to access
#' @return Decrypted secret for the requested_data
#'
#' @export
custom_access_keys <- function(requested_data){
  is_interactive <- custom_interactive()
  if(is_interactive) {
   warning("The function custom_access_keys is deprecated. Please use custom_access_keys_2 instead.") 
  } else if (!interactive()) {
    # Running on Server, no warning should be visible
  } else {
    shiny::showModal(modalDialog(
      title = "Attention",
      "The function custom_access_keys is deprecated. Please use custom_access_keys_2 instead.",
      easyClose = TRUE,
      footer = NULL
    ))
  }
  # decrypt master_key
  key <- key()
  user_name <- user_name()
  path_to_user_db <- "../../base-data/database/shiny_users.sqlite"
  db <- DBI::dbConnect(RSQLite::SQLite(), path_to_user_db)
  master_key_query <- paste0("SELECT encrypted_master_key FROM credentials WHERE user = '", user_name, "'")
  encrypted_master_key <- DBI::dbGetQuery(db, master_key_query)$encrypted_master_key
  master_key <- safer::decrypt_string(encrypted_master_key, key = key)
  DBI::dbDisconnect(db)
  
  # connect to keys_database
  path_to_keys_db <- "../../base-data/database/keys_database.sqlite"
  db <- DBI::dbConnect(RSQLite::SQLite(), path_to_keys_db)
  
  # get the names of all data stored in keys_database
  names_data <- DBI::dbGetQuery(db, "SELECT DISTINCT name FROM keys_database")
  
  # check if the requested data exists in the database
  if (any(grepl(requested_data, names_data$name))) {
    
    # get data
    data <- DBI::dbGetQuery(db, paste("SELECT encrypted_data FROM keys_database WHERE name =", shQuote(requested_data)))
    DBI::dbDisconnect(db)
    
    # decrypt data with master_key and return the secret
    safer::decrypt_string(data$encrypted_data[1], key = master_key)
  } else {
    DBI::dbDisconnect(db)
    return("Error: The requested data does not exist in the database or the name of the requested data is incorrect")
  }
}


#' custom_access_keys_2
#'
#' Loads secret for given name from the keys database and returns the
#' decrypted secret. 
#' When triggered interactively, asks for password of produkt user to decrypt the secret.
#' On the server, the provided password of the signed in user is used.
#'
#' @param name_of_secret Name of the secret to be loaded.
#' @param path_to_keys_db Path to keys_database.sqlite (optional).
#' @param path_to_user_db Path to shiny_users.sqlite (optional).
#' @param preset_key The key to decrypt the data. Default is NA_character_. Please Remove the Key immediately from the environment after your authentication. (optional)
#' @return Decrypted secret for the requested_data.
#' @export
custom_access_keys_2 <- function(name_of_secret,
                                 path_to_keys_db = "../../base-data/database/keys_database.sqlite",
                                 path_to_user_db = "../../base-data/database/shiny_users.sqlite", 
                                 preset_key = NA_character_) {
  credentials <- custom_retrieve_credentials(preset_key = preset_key)
  user_name <- credentials[[1]]
  password <- credentials[[2]]
  
  get_master_key <- tryCatch({
    db <- DBI::dbConnect(RSQLite::SQLite(), path_to_user_db)
    on.exit({
      if (DBI::dbIsValid(db)) {
        DBI::dbDisconnect(db)
      }
    }, add = TRUE)
    
    encrypted_master_key_query <- paste0("SELECT encrypted_master_key FROM credentials WHERE user = '", user_name, "'")
    encrypted_master_key <- DBI::dbGetQuery(db, encrypted_master_key_query)$encrypted_master_key
    
    master_key <- safer::decrypt_string(encrypted_master_key, key = password)
    list(success = TRUE, master_key = master_key)
  }, error = function(e) {
    e$message <- custom_show_warnings(conditionMessage(e), "password", user_name)
    stop(e)
  })
  
  get_secret <- tryCatch({
    db <- DBI::dbConnect(RSQLite::SQLite(), path_to_keys_db)
    on.exit({
      if (DBI::dbIsValid(db)) {
        DBI::dbDisconnect(db)
      }
    }, add = TRUE)
    
    names_data <- DBI::dbGetQuery(db, "SELECT DISTINCT name FROM keys_database")
    
    data <- DBI::dbGetQuery(db, paste("SELECT encrypted_data FROM keys_database WHERE name =", shQuote(name_of_secret)))
    DBI::dbDisconnect(db)
    
    if (!any(grepl(name_of_secret, names_data$name))){
      stop("Error: The name_of_secret does not exist in the database or the name_of_secret is incorrect")
    }
    secret <- safer::decrypt_string(data$encrypted_data[1], key = get_master_key$master_key)
  }, error = function(e) {
    e$message <- custom_show_warnings(conditionMessage(e), "master_key")
    stop(e)
  })
  
  return(secret)
}


#' custom_add_secret
#'
#' Should only be triggered interactively.
#' Encrypts new secret with master_key and stores it in the keys database.
#' Asks for password of produkt user to decrypt master_key and the value of 
#' the new secret to be added.
#'
#' @param name_of_secret Name of the new secret.
#' @param description Description of the new secret (optional).
#' @param path_to_keys_db Path to keys_database.sqlite (optional).
#' @param path_to_user_db Path to shiny_users.sqlite (optional).
#' @return Message indicating the secret has been added.
#' @export
custom_add_secret <- function(name_of_secret, 
                              description = "", 
                              path_to_keys_db = "../../base-data/database/keys_database.sqlite", 
                              path_to_user_db = "../../base-data/database/shiny_users.sqlite") {
  # Enter password to decrypt master_key
  key <- getPass::getPass("Enter password for 'produkt': ")
  new_secret <- getPass::getPass("Enter value of new secret:")
  
  # Decrypt master_key
  master_key <- tryCatch({
    db <- DBI::dbConnect(RSQLite::SQLite(), path_to_user_db)
    on.exit(DBI::dbDisconnect(db), add = TRUE)
    master_key_query <- "SELECT encrypted_master_key FROM credentials WHERE user = 'produkt'"
    encrypted_master_key <- DBI::dbGetQuery(db, master_key_query)$encrypted_master_key
    safer::decrypt_string(encrypted_master_key, key = key)
  }, error = function(e) {
    e$message <- custom_show_warnings(conditionMessage(e), "password")
    stop(e)
  })

  # Encrypt new secret
  encrypted_data <- safer::encrypt_string(new_secret, key = master_key)
  tryCatch({
    db <- DBI::dbConnect(RSQLite::SQLite(), path_to_keys_db)
    on.exit(DBI::dbDisconnect(db), add = TRUE)
    put_query <- paste0("INSERT INTO keys_database (name, encrypted_data, description) VALUES ('", name_of_secret, "', '", encrypted_data, "', '", description, "')")
    DBI::dbExecute(db, put_query)
    cat("Secret has been added")
  }, error = function(e) {
    e$message <- custom_show_warnings(conditionMessage(e), "master_key")
    stop(e)
  })
}


#' custom_show_secrets
#'
#' Should only be triggered interactively.
#' Retrieves all stored names and descriptions from the keys_database.
#'
#' @param path_to_keys_db Path to keys_database.sqlite (optional).
#' @return Dataframe with names and descriptions of stored secrets.
#'
#' @export
custom_show_secrets <- function(path_to_keys_db = "../../base-data/database/keys_database.sqlite") {
  tryCatch({
    db <- DBI::dbConnect(RSQLite::SQLite(), path_to_keys_db)
    on.exit(DBI::dbDisconnect(db), add = TRUE)
    get_query <- "SELECT name, description FROM keys_database"
    data <- DBI::dbGetQuery(db, get_query)
    return(data)
  }, error = function(e) {
    e$message <- custom_show_warnings(conditionMessage(e))
    stop(e)
  })
}


#' custom_delete_secret
#'
#' Should only be triggered interactively.
#' Deletes a secret from the keys_database
#'
#' @param name_of_secret Name of the secret to be deleted.
#' @param path_to_keys_db Path to keys_database.sqlite (optional).
#' @return Message indicating the secret has been deleted.
#' @export
custom_delete_secret <- function(name_of_secret, 
                                 path_to_keys_db = "../../base-data/database/keys_database.sqlite") {
  tryCatch({
    db <- DBI::dbConnect(RSQLite::SQLite(), path_to_keys_db)
    on.exit(DBI::dbDisconnect(db), add = TRUE)
    delete_query <- paste0("DELETE FROM keys_database WHERE name = '", name_of_secret, "'")
    DBI::dbExecute(db, delete_query)
    cat("Secret has been deleted")
  }, error = function(e) {
    e$message <- custom_show_warnings(conditionMessage(e))
    stop(e)
  })
}


#' custom_decrypt_data
#'
#' Decrypts a dataframe with the decrypted content. 
#' The decryption key has to be passed down within a function.
#' Function is deprecated, please use custom_decrypt_data_2.
#'
#' @param decryption_key the secret to decrypt the data with
#' @param encrypted_df encrypted data frames
#'
#' @export
custom_decrypt_data <- function(decryption_key, encrypted_df) {
  is_interactive <- custom_interactive()
  if(is_interactive) {
    warning("The function custom_decrypt_data is deprecated. Please use custom_decrypt_data_2 instead.")
  } else if (!interactive()) {
    # Running on Server, no warning should be visible
  } else {
    shiny::showModal(modalDialog(
      title = "Attention",
      "The function custom_decrypt_data is deprecated. Please use custom_decrypt_data_2 instead.",
      easyClose = TRUE,
      footer = NULL
    ))
  }
  
  encrypted_df %>%
    safer::decrypt_object(decryption_key)
}


#' custom_decrypt_data_2
#'
#' Decrypts a dataframe completely without having to provide the secret.
#'
#' @param encrypted_df Encrypted data frames.
#' @param name_of_secret The name of the secret that decrypts the data.
#' @param path_to_keys_db Path to keys_database.sqlite (optional).
#' @param path_to_user_db Path to shiny_users.sqlite (optional).
#' @return The decrypted dataframe.
#' @export
custom_decrypt_data_2 <- function(encrypted_df,
                                  name_of_secret,
                                  path_to_keys_db = "../../base-data/database/keys_database.sqlite",
                                  path_to_user_db = "../../base-data/database/shiny_users.sqlite") {

  tryCatch({
    decryption_key <- custom_access_keys_2(name_of_secret,
                                           path_to_keys_db = path_to_keys_db,
                                           path_to_user_db = path_to_user_db)
    decrypted_df <- safer::decrypt_object(encrypted_df, decryption_key)
    return(decrypted_df)  
  }, error = function(e) {
    e$message <- custom_show_warnings(conditionMessage(e))
    stop(e)
  })  
}


#' custom_encrypt_data
#'
#' Encrypts a dataframe completely without having to provide the secret.
#'
#' @param data_df The data frame to be encrypted.
#' @param name_of_secret The name of the secret that decrypts the data.
#' @param path_to_keys_db Path to keys_database.sqlite (optional).
#' @param path_to_user_db Path to shiny_users.sqlite (optional).
#' @return The encrypted dataframe .
#' @export
custom_encrypt_data <- function(data_df,
                                name_of_secret,
                                path_to_keys_db = "../../base-data/database/keys_database.sqlite",
                                path_to_user_db = "../../base-data/database/shiny_users.sqlite") {
  tryCatch({
    decryption_key <- custom_access_keys_2(name_of_secret,
                                           path_to_keys_db = path_to_keys_db,
                                           path_to_user_db = path_to_user_db)
    encrypted_df <- safer::encrypt_object(data_df, decryption_key)
    return(encrypted_df)  
  }, error = function(e) {
    e$message <- custom_show_warnings(conditionMessage(e))
    stop(e)
  })  
}


#' custom_encrypt_db
#'
#' This function is used to encrypt a dataframe that is saved within a sqlite database.
#' You are able to specifiy which columns you want to encrypt.
#'
#' @param df The dataframe to be encrypted.
#' @param name_of_secret The name of the secret that encrypts the data.
#' @param columns_to_encrypt The columns that need to be encrpyted.
#' @param base_app Boolean indicating if this function is used in a base_app (Optional)
#' @param key The key (Optional).
#' @param path_to_keys_db Path to keys_database.sqlite (optional).
#' @param path_to_user_db Path to shiny_users.sqlite (optional).
#' @return The specified columns of the database table gets encrypted
#' @export
custom_encrypt_db <- function(df, 
                              name_of_secret, 
                              columns_to_encrypt, 
                              base_app = FALSE, 
                              key = NULL,
                              path_to_keys_db = "../../base-data/database/keys_database.sqlite",
                              path_to_user_db = "../../base-data/database/shiny_users.sqlite") {
  df_encrypted <- df
  columns_to_encrypt <- columns_to_encrypt %||% names(df)
  
  if(!base_app) {
    public_key <- custom_access_keys_2(name_of_secret,
                                       path_to_keys_db = path_to_keys_db,
                                       path_to_user_db = path_to_user_db) 
    
    encrypted_api_key <- readLines("../../keys/BonusDB/bonusDBKey.txt")
    
    key <- safer::decrypt_string(encrypted_api_key, key = public_key)  
  }
  
  df_encrypted[columns_to_encrypt] <- lapply(df[columns_to_encrypt], function(col) {
    sapply(col, function(value) {
      iv <- rand_bytes(16)
      encrypted <- aes_cbc_encrypt(charToRaw(value), key = charToRaw(key), iv = iv)
      base64enc::base64encode(c(iv, encrypted))
    })
  })
  return(as.data.frame(df_encrypted, stringsAsFactors = FALSE))
}


#' custom_decrypt_db
#'
#' This function is used to decrypt a dataframe that is saved within a sqlite database.
#' You are able to specifiy which columns you want to decrypt.
#'
#' @param df The dataframe to be decrypted.
#' @param name_of_secret The name of the secret that decrypts the data.
#' @param columns_to_decrypt The columns that need to be decrpyted.
#' @param base_app Boolean indicating if this function is used in a base_app (Optional).
#' @param key The key (Optional).
#' @param path_to_keys_db Path to keys_database.sqlite (optional).
#' @param path_to_user_db Path to shiny_users.sqlite (optional).
#' @return The specified columns of the database table gets decrypted
#' @export
custom_decrypt_db <- function(df, 
                              name_of_secret, 
                              columns_to_decrypt, 
                              base_app = FALSE, 
                              key = NULL,
                              path_to_keys_db = "../../base-data/database/keys_database.sqlite",
                              path_to_user_db = "../../base-data/database/shiny_users.sqlite") {
  df_decrypted <- df
  columns_to_decrpyt <- columns_to_decrypt %||% names(df)  
  
  if(!base_app) {
    public_key <- custom_access_keys_2(name_of_secret,
                                       path_to_keys_db = path_to_keys_db,
                                       path_to_user_db = path_to_user_db) 
    
    encrypted_api_key <- readLines("../../keys/BonusDB/bonusDBKey.txt")
    
    key <- safer::decrypt_string(encrypted_api_key, key = public_key)  
  }
  
  df_decrypted[columns_to_decrypt] <- lapply(df[columns_to_decrypt], function(col) {
    sapply(col, function(value) {
      if (!is.na(value)) {
        data <- base64enc::base64decode(value)
        iv <- data[1:16] 
        encrypted_data <- data[-(1:16)] 
        decrypted <- aes_cbc_decrypt(encrypted_data, key = charToRaw(key), iv = iv)
        rawToChar(decrypted)
      } else {
        NA
      }
    })
  })
  return(as.data.frame(df_decrypted, stringsAsFactors = FALSE))
}


#' custom_permission_level
#'
#' Returns an integer telling you hat level of permission the user has.
#' This function does not need any parameters.
#'
#' @param path_to_user_db The path to the user database. Default is "../../base-data/database/shiny_users.sqlite". (optional)
#' @param preset_key The key to decrypt the data. Default is NA_character_. Please Remove the Key immediately from the environment after your authentication. (optional)
#' @return An integer representing the user's permission level.
#' @export
custom_permission_level <- function(path_to_user_db = "../../base-data/database/shiny_users.sqlite", preset_key = NA_character_) {
  
  user_name <- custom_retrieve_credentials(password = FALSE, preset_key = preset_key)[[1]]
  
  permission <- tryCatch({
    db <- DBI::dbConnect(RSQLite::SQLite(), path_to_user_db)
    on.exit(DBI::dbDisconnect(db), add = TRUE)
    
    permission_query <- paste0("SELECT permission FROM credentials WHERE user = '", user_name, "'")
    result <- DBI::dbGetQuery(db, permission_query)
    
    if (length(result$permission) == 0) {
      stop(sprintf("The user '%s' was not found in the users database.", user_name))
    }
    
    result$permission
  }, error = function(e) {
    e$message <- custom_show_warnings(conditionMessage(e), "user_db")
    stop(e)
  })
  

  determine_permission_level <- function(permission) {
    permission_level <- tryCatch({
      dplyr::case_when(
        permission %in% c("Admin", "Entwickler", "Geschaeftsfuerung", "Headof", "Verwaltung") ~ 2,
        permission %in% c("Teamlead") ~ 1,
        TRUE ~ 0
      )
    }, error = function(e) {
      e$message <- custom_show_warnings(conditionMessage(e))
      stop(e)
    })
    
    return(permission_level)
  }
  
  return(determine_permission_level(permission))
}


#' custom_username
#'
#' This function is used to retrieve the username of the user.
#'
#' @param preset_key The key to decrypt the data. Default is NA_character_. Please Remove the Key immediately from the environment after your authentication. (optional)
#' @return The username
#' @export
custom_username <- function(preset_key = NA_character_) {
  user_name <- custom_retrieve_credentials(password = FALSE, preset_key = preset_key)[[1]]
  return(user_name)
}


#' custom_retrieve_credentials
#'
#' This function is used to retrieve the credentials of the user.
#'
#' @param username Boolean indicating if the user_name should be retrieved. Default is TRUE (optional).
#' @param password Boolean indicating if the password should be retrieved. Default is TRUE (optional).
#' @param preset_key The key to decrypt the data. Default is NA_character_. Please Remove the Key immediately from the environment after your authentication. (optional)
#' @return List which contains the user_name and password
#' @export
custom_retrieve_credentials <- function(username = TRUE, password = TRUE, preset_key = NA_character_) {
  is_interactive <- custom_interactive()
  
  retrieve_user_name <- function(){
    if (!username) {
      return()
    }
    if (is_interactive) {
      return("produkt")
    } else {
      return(user_name())
    }
  }
  
  retrieve_password <- function(){
    if(!password) {
      return()
    }
    if(is_interactive) {
      if(is.na(preset_key)) {
        return(getPass::getPass(msg = "Gib das Passwort für den Produktnutzer ein:"))
      } else {
        return(preset_key)
      }
    } else {
      return(key()) 
    }
  } 
  
  user_name <- retrieve_user_name()
  password <- retrieve_password()
  
  return(list(user_name, password))
}


#' custom_show_warnings
#'
#' This function shows the warning of any custom function.
#' If a shiny app is started, the warning pops up on the dashboard.
#' If a function is called locally, the warning is printed on the console. 
#'
#' @param warning The warning a try-catch block throws
#' @param param Parameter used to distinguish between errors (Optional).
#' @param username Used to print the username if not found in the database (Optional).
#' @return The modified warning message or NULL if the warning is to be suppressed.
#' @export
custom_show_warnings <- function(warning, param = NA, username = NA){
  warning_output <- dplyr::case_when(
    warning == "Unable to decrypt. Ensure that the input was generated by 'encrypt_string'." && param == "password" ~ "Unable to decrypt encrypted_master_key with the given password.",
    warning == "Unable to decrypt. Ensure that the input was generated by 'encrypt_string'." && param == "master_key" ~ "Unable to decrypt encrypted_data with the given master_key.",
    warning == "string is not a string (a length one character vector). or string is not a raw vector" && param == "password" || warning == "Zeichenkette ist keine Zeichenkette (ein Vektor der Länge eins). oder Zeichenkette ist kein Raw-Vektor." && param == "password" ~ sprintf("The user '%s' was not found in the users database. This user is important to manage the user and key database.", username),
    TRUE ~ warning
  )
  return(warning_output)
}


#' custom_interactive
#'
#' This function checks if a function is called from a shiny app or from the console.
#' It works just like interactive(), but returns FALSE if running from a shiny app.
#'
#' @return Boolean value indicating if a function is called from a shiny app or console
custom_interactive <- function(){
  if (!is.null(shiny::getDefaultReactiveDomain())) {
    return(FALSE)
  }
  return(interactive())
}

#' custom_load_data_in_module
#'
#' @param data_file This can be an Data Frame for example TestData or the path (string) to the data file
#' @param name_of_secret Only necessary if the data is encrypted: The name of the secret in the keys database that decrypts the data
#' @return Returns the loaded data as a dataframe.
#' @details If the data is encrypted (detected by it being of type `raw`), the function attempts to decrypt it using `shinymanager::custom_decrypt_data_2()`.
#' @examples
#' # Load unencrypted data frame
#' data <- custom_load_shiny_module_data(TestData)
#' 
#' # Load encrypted data and decrypt it
#' data <- custom_load_shiny_module_data("cars_encrypted.RDS", name_of_secret = "billomat_db_key")
#' @export
custom_load_data_in_module <- function(data_file, name_of_secret) {
  # ---- start ---- #
  # Use data_file as dataframe or path
  if (is.data.frame(data_file)) {
    data_df <- data_file
  } else if (is.character(data_file)) {
    data_df <- readRDS(data_file)
    
    if (is.raw(data_df)) {
      data_df <- shinymanager::custom_decrypt_data_2(data_file, name_of_secret)
    }
    
  } else if (is.raw(data_file)) {
    # if (!is.character(name_of_secret)) { # Test if secret available
    #   stop(
    #     "The data in data_file is encrypted. In order to decrypt the data, you have to pass the correct name_of_secret"
    #   )
    # } else {
      data_df <- shinymanager::custom_decrypt_data_2(data_file, name_of_secret)
    # }
  } else {
    stop("The 'data_file'-Parameter has to be an Path (String) or an (encrypted) data frame.")
  }
  
  # check if data is encrypted (raw type)
  # if (is.raw(data_file)) {
  #   # Ensure name_of_secret is provided for decryption
  #   if (!is.character(name_of_secret)) { # Test if secret available
  #     stop(
  #       "The data in data_file is encrypted. In order to decrypt the data, you have to pass the correct name_of_secret"
  #     )
  #   } else {
  #     data_df <- shinymanager::custom_decrypt_data_2(data_file, name_of_secret)
  #   }
  # }
  
  return(data_df)
  
}

#' custom_filter_teamlead
#' 
#' Filters sales_teams dataframe to extract only Sales MA in 
#' specific team of Teamlead (employee).
#'
#' @param sales_teams dataframe containing information about all sales employees
#' @param employee sales employee/logged in user name
#' @param user_permission permission level of the user
#' @param datebase_needed Logical value (TRUE or FALSE) indicating if the database format is needed.
#' @return return name of vector of names of Sales Mitarbeiter in Team
#' @export
custom_filter_teamleads = function(sales_teams, employee, user_permission, database_needed) {
  if (employee %in% sales_teams$Team) {
    sales_teams <- sales_teams %>%
      filter(Team == employee) %>%
      mutate(Mitarbeiter = paste(Vorname, Nachname)) %>%
      select(Team, Mitarbeiter)
    
    neuer_mitarbeiter <- unique(sales_teams$Team)
    neue_zeile <- data.frame(Team = neuer_mitarbeiter, Mitarbeiter = neuer_mitarbeiter)
    sales_teams <- bind_rows(sales_teams, neue_zeile)
    sales_teams <- sales_teams %>%
      select(Mitarbeiter)
  } else if (employee == "produkt"|user_permission == 2) {
    sales_teams <- sales_teams %>% 
      mutate(Mitarbeiter = paste(Vorname, Nachname)) %>%
      distinct(Mitarbeiter)
  } else {
    sales_teams <- sales_teams %>% 
      mutate(Mitarbeiter = paste(Vorname, Nachname)) %>% 
      distinct(Mitarbeiter) %>% 
      filter(employee == Mitarbeiter)
  }
     employee_list <- sales_teams[, "Mitarbeiter"]
     
  if (database_needed) {
    employee_list <- paste(shQuote(employee_list, type = "sh"), collapse = ", ")
  } 
  
  return(employee_list)
}

#' custom_retrieve_user_role
#' 
#' Retrieves the role of a user from the database.
#'
#' @param path_to_user_db Path to the SQLite database containing user credentials.
#' @param preset_key The key to decrypt the data. Default is NA_character_. Please Remove the Key immediately from the environment after your authentication. (optional)
#' @return Returns the role name of the user.
#' @export
custom_retrieve_user_role <- function(path_to_user_db = "../../base-data/database/shiny_users.sqlite", preset_key = NA_character_){
  user_name <- custom_retrieve_credentials(password = FALSE, preset_key = preset_key)[[1]]
  permission <- tryCatch({
    db <- DBI::dbConnect(RSQLite::SQLite(), path_to_user_db)
    on.exit(DBI::dbDisconnect(db), add = TRUE)
    permission_query <- paste0("SELECT permission FROM credentials WHERE user = '", 
                               user_name, "'")
    result <- DBI::dbGetQuery(db, permission_query)
    if (length(result$permission) == 0) {
      stop(sprintf("The user '%s' was not found in the users database.", 
                   user_name))
    }
    result$permission
  }, error = function(e) {
    e$message <- custom_show_warnings(conditionMessage(e), 
                                      "user_db")
    stop(e)
  })
  
  return(permission)
}

