const express = require("express");
const { Pool } = require("pg");
const bcrypt = require("bcryptjs");

require('dotenv').config();

const app = express();
const PORT = 3000;

// DB connection pool
const pool = new Pool({
  host: process.env.DB_HOST,
  port: process.env.DB_PORT,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME
});

app.use(express.json());

// Health check (public)
app.get("/health", (req, res) => {
  res.json({ status: "ok" });
});

app.get("/", (req, res) => {
  res.send(`
    <!doctype html>
    <html>
      <head>
        <meta charset="utf-8" />
        <title>Auth Demo</title>
      </head>
      <body>
        <h1>Register</h1>
        <form id="registerForm">
          <input name="username" placeholder="Username" required />
          <input name="password" type="password" placeholder="Password" required />
          <button type="submit">Register</button>
        </form>
        <pre id="registerResult"></pre>

        <h1>Login</h1>
        <form id="loginForm">
          <input name="username" placeholder="Username" required />
          <input name="password" type="password" placeholder="Password" required />
          <button type="submit">Login</button>
        </form>
        <pre id="loginResult"></pre>

        <script>
          async function handleForm(formId, url, resultId) {
            const form = document.getElementById(formId);
            form.addEventListener("submit", async (e) => {
              e.preventDefault();
              const data = Object.fromEntries(new FormData(form).entries());
              const res = await fetch(url, {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify(data),
              });
              const json = await res.json();
              document.getElementById(resultId).textContent =
                JSON.stringify(json, null, 2);
            });
          }

          handleForm("registerForm", "/register", "registerResult");
          handleForm("loginForm", "/login", "loginResult");
        </script>
      </body>
    </html>
  `);
});


// Register endpoint
app.post("/register", async (req, res) => {
  const { username, password } = req.body;

  if (!username || !password) {
    return res.status(400).json({ error: "Missing username or password", code: "MISSING_FIELDS" });
  }

  if (username.length < 3 || username.length > 50) {
    return res.status(400).json({ error: "Username must be 3-50 characters", code: "INVALID_USERNAME" });
  }

  if (password.length < 8) {
    return res.status(400).json({ error: "Password must be at least 8 characters", code: "WEAK_PASSWORD" });
  }

  try {
    // Check if user already exists
    const existing = await pool.query("SELECT id FROM users WHERE username = $1", [username]);
    if (existing.rowCount > 0) {
      console.log(`[${new Date().toISOString()}] REGISTER_FAILED: username=${username} reason=already_exists`);
      return res.status(409).json({ error: "User already exists", code: "USER_EXISTS" });
    }

    // Hash password with bcrypt
    const passwordHash = bcrypt.hashSync(password, 10);

    // Insert new user
    const result = await pool.query(
      "INSERT INTO users (username, password_hash, role) VALUES ($1, $2, $3) RETURNING id, username, role",
      [username, passwordHash, "user"]
    );

    const user = result.rows[0];
    console.log(`[${new Date().toISOString()}] REGISTER_SUCCESS: username=${username}`);

    return res.status(201).json({
      message: "User registered successfully",
      user: { id: user.id, username: user.username, role: user.role }
    });
  } catch (err) {
    console.error("Error in /register:", err);
    return res.status(500).json({ error: "Internal server error", code: "SERVER_ERROR" });
  }
});

// Login endpoint
app.post("/login", async (req, res) => {
  const { username, password } = req.body;

  if (!username || !password) {
    return res.status(400).json({ error: "Missing credentials", code: "MISSING_FIELDS" });
  }

  try {
    const result = await pool.query(
      "SELECT id, username, password_hash, role FROM users WHERE username = $1",
      [username]
    );

    if (result.rowCount === 0) {
      console.log(`[${new Date().toISOString()}] LOGIN_FAILED: username=${username} reason=user_not_found`);
      return res.status(401).json({ error: "Invalid username or password", code: "AUTH_FAILED" });
    }

    const user = result.rows[0];
    const passwordMatch = bcrypt.compareSync(password, user.password_hash);

    if (!passwordMatch) {
      console.log(`[${new Date().toISOString()}] LOGIN_FAILED: username=${username} reason=wrong_password`);
      return res.status(401).json({ error: "Invalid username or password", code: "AUTH_FAILED" });
    }

    console.log(`[${new Date().toISOString()}] LOGIN_SUCCESS: username=${username}`);

    return res.status(200).json({
      message: "Login successful",
      user: { id: user.id, username: user.username, role: user.role }
    });
  } catch (err) {
    console.error("Error in /login:", err);
    return res.status(500).json({ error: "Internal server error", code: "SERVER_ERROR" });
  }
});

app.listen(PORT, () => {
  console.log(`Web API listening on port ${PORT}`);
});
