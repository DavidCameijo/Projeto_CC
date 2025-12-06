const express = require("express");
const { Pool } = require("pg");
const bcrypt = require("bcryptjs");
const jwt = require("jsonwebtoken");
const speakeasy = require("speakeasy");
const QRCode = require("qrcode");
const rateLimit = require("express-rate-limit");
const crypto = require("crypto");
const fs = require("fs");

require('dotenv').config();

const app = express();
const PORT = process.env.PORT || 3000;

// DB connection pool
const pool = new Pool({
  host: process.env.DB_HOST,
  port: process.env.DB_PORT,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME
});

app.use(express.json());

// ==================== CONFIG INTEGRITY CHECK ====================
function verifyConfigIntegrity() {
  const envPath = '.env';
  if (!fs.existsSync(envPath)) {
    console.warn('[SECURITY] .env file not found');
    return;
  }
  
  const secret = process.env.JWT_SECRET || 'default-secret';
  const hash = crypto
    .createHmac('sha256', secret)
    .update(fs.readFileSync(envPath))
    .digest('hex');
  
  console.log(`[CONFIG] Integrity hash: ${hash.substring(0, 16)}...`);
}

// ==================== RATE LIMITERS ====================
const registerLimiter = rateLimit({
  windowMs: 60 * 60 * 1000, // 1 hour
  max: 3, // 3 registrations per hour per IP
  message: 'Too many registration attempts, try again later',
  standardHeaders: true,
  legacyHeaders: false,
});

const loginLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 5, // 5 attempts per 15 min
  message: 'Too many login attempts, try again later',
  standardHeaders: true,
  legacyHeaders: false,
  skip: (req) => req.path === '/health',
});

// ==================== MIDDLEWARE ====================
function authenticateToken(req, res, next) {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ');

  if (!token) {
    return res.status(401).json({ error: "Access token required", code: "NO_TOKEN" });
  }

  jwt.verify(token, process.env.JWT_SECRET || 'default-secret', (err, user) => {
    if (err) {
      console.log(`[AUTH] Token verification failed: ${err.message}`);
      return res.status(403).json({ error: "Invalid or expired token", code: "INVALID_TOKEN" });
    }
    req.user = user;
    next();
  });
}

// ==================== PUBLIC ENDPOINTS ====================
app.get("/health", (req, res) => {
  res.json({ status: "ok", timestamp: new Date().toISOString() });
});

app.get("/", (req, res) => {
  res.send(`
    <!doctype html>
    <html>
      <head>
        <meta charset="utf-8" />
        <title>Auth Demo with 2FA</title>
        <style>
          body { font-family: Arial, sans-serif; max-width: 800px; margin: 50px auto; }
          .section { margin-bottom: 40px; border: 1px solid #ccc; padding: 20px; }
          input { display: block; margin: 10px 0; padding: 8px; width: 100%; }
          button { padding: 10px 20px; background: #007bff; color: white; border: none; cursor: pointer; }
          pre { background: #f4f4f4; padding: 10px; overflow-x: auto; }
        </style>
      </head>
      <body>
        <h1>🔐 Secure Authentication System</h1>

        <div class="section">
          <h2>Step 1: Register New User</h2>
          <form id="registerForm">
            <input name="username" placeholder="Username (3-50 chars)" required />
            <input name="password" type="password" placeholder="Password (min 8 chars)" required />
            <button type="submit">Register</button>
          </form>
          <pre id="registerResult"></pre>
        </div>

        <div class="section">
          <h2>Step 2: Setup 2FA (After Register)</h2>
          <p>Scan QR code with Google Authenticator or Authy</p>
          <div id="qrCodeContainer"></div>
          <p>Or enter manually: <code id="secretCode"></code></p>
        </div>

        <div class="section">
          <h2>Step 3: Login with 2FA</h2>
          <form id="loginForm">
            <input name="username" placeholder="Username" required />
            <input name="password" type="password" placeholder="Password" required />
            <input name="otp" placeholder="6-digit OTP from Authenticator" required maxlength="6" />
            <button type="submit">Login</button>
          </form>
          <pre id="loginResult"></pre>
        </div>

        <div class="section">
          <h2>Step 4: Access Protected Resource</h2>
          <input id="tokenInput" placeholder="Paste JWT token here" style="margin-bottom: 10px;" />
          <button onclick="testProtected()">Test Protected Endpoint</button>
          <pre id="protectedResult"></pre>
        </div>

        <script>
          document.getElementById('registerForm').addEventListener('submit', async (e) => {
            e.preventDefault();
            const data = Object.fromEntries(new FormData(e.target).entries());
            try {
              const res = await fetch('/register', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(data),
              });
              const json = await res.json();
              document.getElementById('registerResult').textContent = JSON.stringify(json, null, 2);
              
              if (json.qrCode) {
                document.getElementById('qrCodeContainer').innerHTML = '<img src="' + json.qrCode + '" />';
                document.getElementById('secretCode').textContent = json.secret;
              }
            } catch (err) {
              document.getElementById('registerResult').textContent = 'Error: ' + err.message;
            }
          });

          document.getElementById('loginForm').addEventListener('submit', async (e) => {
            e.preventDefault();
            const data = Object.fromEntries(new FormData(e.target).entries());
            try {
              const res = await fetch('/login', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(data),
              });
              const json = await res.json();
              document.getElementById('loginResult').textContent = JSON.stringify(json, null, 2);
              
              if (json.token) {
                localStorage.setItem('authToken', json.token);
                document.getElementById('tokenInput').value = json.token;
              }
            } catch (err) {
              document.getElementById('loginResult').textContent = 'Error: ' + err.message;
            }
          });

          function testProtected() {
            const token = document.getElementById('tokenInput').value;
            if (!token) {
              document.getElementById('protectedResult').textContent = 'Please paste token first';
              return;
            }
            fetch('/profile', {
              method: 'GET',
              headers: { 'Authorization': 'Bearer ' + token }
            }).then(r => r.json()).then(json => {
              document.getElementById('protectedResult').textContent = JSON.stringify(json, null, 2);
            }).catch(err => {
              document.getElementById('protectedResult').textContent = 'Error: ' + err.message;
            });
          }
        </script>
      </body>
    </html>
  `);
});

// ==================== REGISTER ====================
app.post("/register", registerLimiter, async (req, res) => {
  const { username, password } = req.body;

  if (!username || !password) {
    return res.status(400).json({ 
      error: "Missing username or password", 
      code: "MISSING_FIELDS" 
    });
  }

  if (username.length < 3 || username.length > 50) {
    return res.status(400).json({ 
      error: "Username must be 3-50 characters", 
      code: "INVALID_USERNAME" 
    });
  }

  if (password.length < 8) {
    return res.status(400).json({ 
      error: "Password must be at least 8 characters", 
      code: "WEAK_PASSWORD" 
    });
  }

  try {
    const existing = await pool.query(
      "SELECT id FROM users WHERE username = $1",
      [username]
    );
    
    if (existing.rowCount > 0) {
      console.log(`[REGISTER] FAILED: username=${username} reason=already_exists`);
      return res.status(409).json({ 
        error: "User already exists", 
        code: "USER_EXISTS" 
      });
    }

    const passwordHash = bcrypt.hashSync(password, 10);

    const secret = speakeasy.generateSecret({
      name: `SecureAuth (${username})`,
      issuer: 'SecureAuth',
    });

    const result = await pool.query(
      `INSERT INTO users (username, password_hash, role, two_factor_secret, two_factor_enabled) 
       VALUES ($1, $2, $3, $4, $5) 
       RETURNING id, username, role`,
      [username, passwordHash, "user", secret.base32, false]
    );

    const user = result.rows;
    const qrCode = await QRCode.toDataURL(secret.otpauth_url);

    console.log(`[REGISTER] SUCCESS: username=${username} id=${user.id}`);

    return res.status(201).json({
      message: "User registered. Scan QR code to enable 2FA.",
      user: { id: user.id, username: user.username, role: user.role },
      qrCode: qrCode,
      secret: secret.base32,
      note: "Save the secret in a secure location"
    });

  } catch (err) {
    console.error("[REGISTER] ERROR:", err);
    return res.status(500).json({ 
      error: "Internal server error", 
      code: "SERVER_ERROR" 
    });
  }
});

// ==================== LOGIN ====================
app.post("/login", loginLimiter, async (req, res) => {
  const { username, password, otp } = req.body;

  if (!username || !password) {
    return res.status(400).json({ 
      error: "Missing credentials", 
      code: "MISSING_FIELDS" 
    });
  }

  if (!otp) {
    return res.status(400).json({ 
      error: "OTP required for 2FA", 
      code: "OTP_REQUIRED" 
    });
  }

  try {
    const result = await pool.query(
      "SELECT id, username, password_hash, role, two_factor_secret FROM users WHERE username = $1",
      [username]
    );

    if (result.rowCount === 0) {
      console.log(`[LOGIN] FAILED: username=${username} reason=user_not_found`);
      return res.status(401).json({ 
        error: "Invalid username or password", 
        code: "AUTH_FAILED" 
      });
    }

    const user = result.rows;

    const passwordMatch = bcrypt.compareSync(password, user.password_hash);
    if (!passwordMatch) {
      console.log(`[LOGIN] FAILED: username=${username} reason=invalid_password`);
      return res.status(401).json({ 
        error: "Invalid username or password", 
        code: "AUTH_FAILED" 
      });
    }

    if (!user.two_factor_secret) {
      console.log(`[LOGIN] FAILED: username=${username} reason=2fa_not_setup`);
      return res.status(401).json({ 
        error: "2FA not configured for this user", 
        code: "2FA_NOT_SETUP" 
      });
    }

    const otpValid = speakeasy.totp.verify({
      secret: user.two_factor_secret,
      encoding: 'base32',
      token: otp,
      window: 2,
    });

    if (!otpValid) {
      console.log(`[LOGIN] FAILED: username=${username} reason=invalid_otp`);
      return res.status(401).json({ 
        error: "Invalid OTP", 
        code: "INVALID_OTP" 
      });
    }

    const token = jwt.sign(
      {
        id: user.id,
        username: user.username,
        role: user.role,
        iat: Math.floor(Date.now() / 1000),
      },
      process.env.JWT_SECRET || 'default-secret',
      { expiresIn: '15m' }
    );

    console.log(`[LOGIN] SUCCESS: username=${username} id=${user.id}`);

    return res.status(200).json({
      message: "Login successful with 2FA verified",
      token: token,
      user: { id: user.id, username: user.username, role: user.role },
      expiresIn: '15 minutes'
    });

  } catch (err) {
    console.error("[LOGIN] ERROR:", err);
    return res.status(500).json({ 
      error: "Internal server error", 
      code: "SERVER_ERROR" 
    });
  }
});

// ==================== PROTECTED ENDPOINTS ====================
app.get("/profile", authenticateToken, async (req, res) => {
  try {
    const result = await pool.query(
      "SELECT id, username, role FROM users WHERE id = $1",
      [req.user.id]
    );

    if (result.rowCount === 0) {
      return res.status(404).json({ error: "User not found" });
    }

    const user = result.rows;
    console.log(`[PROFILE] Accessed by: username=${user.username}`);

    return res.status(200).json({
      message: "User profile retrieved successfully",
      user: user
    });

  } catch (err) {
    console.error("[PROFILE] ERROR:", err);
    return res.status(500).json({ 
      error: "Internal server error", 
      code: "SERVER_ERROR" 
    });
  }
});

// ==================== STARTUP ====================
verifyConfigIntegrity();

app.listen(PORT, () => {
  console.log(`[SERVER] Web API listening on port ${PORT}`);
  console.log(`[SERVER] 2FA enabled with TOTP (Time-based OTP)`);
  console.log(`[SERVER] Health check: GET /health`);
});
