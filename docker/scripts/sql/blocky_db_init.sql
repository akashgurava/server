\set blocky_username `echo "$BLOCKY_USERNAME"`
\set blocky_pwd `echo "$BLOCKY_PASSWORD"`
\set blocky_db `echo "$BLOCKY_DATABASE_NAME"`

CREATE ROLE :blocky_username WITH
	LOGIN
	CREATEDB
	BYPASSRLS
	CONNECTION LIMIT -1
	PASSWORD :'blocky_pwd';

SET ROLE :blocky_username;

CREATE DATABASE :blocky_db;
