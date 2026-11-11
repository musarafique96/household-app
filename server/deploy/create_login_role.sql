-- Login role for the Gharbaar API. Least privilege: it can read and change data, but it doesn't own
-- the database, can't change the schema, and doesn't bypass row-level security.
-- Run by the login-role step after migrations. The password comes from the psql variable pw.

SELECT 'CREATE ROLE gharbaar_login' WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'gharbaar_login') \gexec
SELECT format('ALTER ROLE gharbaar_login WITH LOGIN NOSUPERUSER NOBYPASSRLS PASSWORD %L', :'pw') \gexec

GRANT USAGE ON SCHEMA public TO gharbaar_login;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO gharbaar_login;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO gharbaar_login;

-- Tables and sequences that later migrations create get the same grants.
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO gharbaar_login;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO gharbaar_login;
