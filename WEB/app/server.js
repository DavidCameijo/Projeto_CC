const express = require("express");
const { Pool } = require("pg");
const bcrypt = require("bcryptjs");
const crypto = require("crypto");

const app = express();
const PORT = 3000;

// DB connection pool
const pool = new Pool({
  host: "db01",
  port: 5432,
  user: "admin",
  password: "admin123",
  database: "projeto_cc"
});

// In-memory session store
const sessions = new Map();

app.use(express.json());

// Health check (public)
app.get("/health", (req, res) => {
  res.json({ status: "ok" });
});

// Auth middleware
function authRequired(req, res, next) {
  const authHeader = req.headers["authorization"];
  if (!authHeader || !authHeader.startsWith("Bearer ")) {
    return res.status(401).json({ error: "Missing or invalid Authorization header" });
  }

  const token = authHeader.substring("Bearer ".length);
  const session = sessions.get(token);
  if (!session) {
    return res.status(401).json({ error: "Invalid or expired token" });
  }

  req.user = session;
  next();
}

function adminOnly(req, res, next) {
  if (!req.user || req.user.role !== "admin") {
    return res.status(403).json({ error: "Admin role required" });
  }
  next();
}

// Login
app.post("/login", async (req, res) => {
  const { username, password } = req.body;

  if (!username || !password) {
    return res.status(400).json({ error: "Missing credentials" });
  }

  try {
    const result = await pool.query(
      "SELECT id, username, password_hash, role FROM users WHERE username = $1",
      [username]
    );

    if (result.rowCount === 0) {
      return res.status(401).json({ error: "Invalid username or password" });
    }

    const user = result.rows[0];
    const ok = bcrypt.compareSync(password, user.password_hash);

    if (!ok) {
      return res.status(401).json({ error: "Invalid username or password" });
    }

    // Create session token
    const token = crypto.randomBytes(24).toString("hex");
    sessions.set(token, {
      userId: user.id,
      username: user.username,
      role: user.role
    });

    return res.json({
      message: "Login successful",
      token,
      role: user.role
    });
  } catch (err) {
    console.error("Error in /login:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

// GET feriados (any logged-in user)
app.get("/feriados", authRequired, async (req, res) => {
  try {
    const result = await pool.query(
      "SELECT id, day, month, description FROM feriados ORDER BY month, day"
    );
    const formatted = result.rows.map(f => ({
      id: f.id,
      day: f.day,
      month: f.month,
      description: f.description,
      label: `${f.day}-${f.month} - ${f.description}`
    }));
    res.json(formatted);
  } catch (err) {
    console.error("Error querying feriados:", err);
    res.status(500).json({ error: "DB error" });
  }
});

// POST feriado (admin only)
app.post("/feriados", authRequired, adminOnly, async (req, res) => {
  const { day, month, description } = req.body;

  if (!day || !month || !description) {
    return res.status(400).json({ error: "Missing day, month or description" });
  }

  try {
    const result = await pool.query(
      "INSERT INTO feriados (day, month, description) VALUES ($1, $2, $3) RETURNING id, day, month, description",
      [day, month, description]
    );
    res.status(201).json(result.rows[0]);
  } catch (err) {
    console.error("Error inserting feriado:", err);
    res.status(500).json({ error: "DB error" });
  }
});

app.listen(PORT, () => {
  console.log(`Web API listening on port ${PORT}`);
});
