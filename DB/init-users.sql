-- Create additional databases
CREATE DATABASE "admin";
CREATE DATABASE "Projeto_CC";

-- Create custom roles/users if they don't exist
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_user WHERE usename = 'admin') THEN
    CREATE ROLE admin WITH LOGIN PASSWORD 'admin123';
  END IF;
END
$$;

-- Grant privileges
ALTER ROLE admin WITH SUPERUSER CREATEDB CREATEROLE;

-- Create application tables in the main database
CREATE TABLE IF NOT EXISTS users (
  id SERIAL PRIMARY KEY,
  username TEXT UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  role TEXT NOT NULL,
  two_factor_secret TEXT,
  two_factor_enabled BOOLEAN DEFAULT FALSE
);

INSERT INTO users (username, password_hash, role,two_factor_enabled) VALUES
  ('admin', '$2a$10$/JKoT9mRo00QZgBlunx4DeT/PWdDFPj/KoM0sQaA6Gl4NiH0kYq6G', 'admin',FALSE),
  ('user', '$2a$10$8t7druW5fOHrlNYz39OLT..Nfx2xTG38oWs7WAkgYWe8MlrCAWgsC', 'reader',FALSE)
ON CONFLICT (username) DO NOTHING;