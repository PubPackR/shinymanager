-- SQLite, NOT PostgreSQL.
--
-- Run in DBeaver against a FRESH copy of base-data/database/shiny_users.sqlite
-- from the server. It returns one text cell: a VALUES list
-- (user, permission, applications) for every row of credentials.
--
-- Copy the cell into the marked place in check_shiny_accounts.sql. Never commit
-- the result: it contains personal names. Delete the SQLite copy afterwards.
--
-- No password hash, no encrypted_master_key leaves the file.

SELECT group_concat(
         printf('(%Q, %Q, %Q)', user, permission, applications),
         ',' || char(10)
       ) AS values_list
FROM credentials;
