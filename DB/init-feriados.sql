CREATE TABLE IF NOT EXISTS feriados (
  id SERIAL PRIMARY KEY,
  day INTEGER NOT NULL,
  month INTEGER NOT NULL,
  description TEXT NOT NULL
);

INSERT INTO feriados (day, month, description) VALUES
  (1, 12, 'Dia da Independência'),
  (25, 12, 'Natal');