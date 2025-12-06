CREATE TABLE IF NOT EXISTS users (
  id SERIAL PRIMARY KEY,
  username TEXT UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  role TEXT NOT NULL,
  two_factor_secret TEXT,
);

INSERT INTO users (username, password_hash, role) VALUES
  ('admin', '$2a$10$/JKoT9mRo00QZgBlunx4DeT/PWdDFPj/KoM0sQaA6Gl4NiH0kYq6G', 'admin'),
  ('user', '$2a$10$8t7druW5fOHrlNYz39OLT..Nfx2xTG38oWs7WAkgYWe8MlrCAWgsC', 'reader')

  
ON CONFLICT (username) DO NOTHING;