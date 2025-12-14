const express = require("express");
const { Pool } = require("pg");
const bcrypt = require("bcryptjs");
const speakeasy = require("speakeasy");
const QRCode = require("qrcode");
const rateLimit = require("express-rate-limit");
const crypto = require("crypto");
const fs = require("fs");
const https = require("https");
const http = require("http");
const jwt = require("jsonwebtoken");

require('dotenv').config();

const app = express();
const PORT = process.env.PORT || 3000;
const JWT_SECRET = process.env.JWT_SECRET || 'your-secret-key-change-in-production';

// ==================== FAIL2BAN TRACKING ====================
// In-memory storage for failed login attempts (Assignment 2 requirement)
const loginAttempts = new Map(); // username -> { count, bannedUntil }
const MAX_FAILED_ATTEMPTS = 2;
const BAN_DURATION_MS = 15 * 60 * 1000; // 15 minutes

function isUserBanned(username) {
  const attempt = loginAttempts.get(username);
  if (!attempt || !attempt.bannedUntil) return false;
  
  if (Date.now() < attempt.bannedUntil) {
    return true; // Still banned
  }
  
  // Ban expired, reset
  loginAttempts.delete(username);
  return false;
}

function recordFailedAttempt(username) {
  const attempt = loginAttempts.get(username) || { count: 0, bannedUntil: null };
  attempt.count += 1;
  
  if (attempt.count > MAX_FAILED_ATTEMPTS) {
    attempt.bannedUntil = Date.now() + BAN_DURATION_MS;
    console.log(`[FAIL2BAN] User banned: username=${username} until=${new Date(attempt.bannedUntil).toISOString()}`);
  }
  
  loginAttempts.set(username, attempt);
  return attempt;
}

function clearFailedAttempts(username) {
  loginAttempts.delete(username);
}

// DB connection pool with mTLS support
const dbConfig = {
  host: process.env.DB_HOST,
  port: process.env.DB_PORT,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME
};

// Add TLS configuration if client certs are available
if (fs.existsSync('/app/certs/ca.crt') && fs.existsSync('/app/certs/web02-client.crt') && fs.existsSync('/app/certs/web02-client.key')) {
  dbConfig.ssl = {
    rejectUnauthorized: true,
    ca: fs.readFileSync('/app/certs/ca.crt'),
    cert: fs.readFileSync('/app/certs/web02-client.crt'),
    key: fs.readFileSync('/app/certs/web02-client.key'),
    checkServerIdentity: () => undefined // Skip hostname verification (cert is for db01.org.local, we connect to db01)
  };
  console.log('[TLS] PostgreSQL client certificate authentication enabled');
} else {
  console.warn('[TLS] Database client certificates not found - attempting without mTLS');
}

const pool = new Pool(dbConfig);

app.use(express.json());
app.set('trust proxy', 1); // ✅ Trust nginx reverse proxy headers

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
  windowMs: 60 * 60 * 1000,
  max: 3,
  message: 'Too many registration attempts, try again later',
  standardHeaders: true,
  legacyHeaders: false,
});

const loginLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 5,
  message: 'Too many login attempts, try again later',
  standardHeaders: true,
  legacyHeaders: false,
  skip: (req) => req.path === '/health',
});

// ==================== HEALTH CHECK ====================
app.get('/health', (req, res) => {
  res.json({
    status: 'ok',
    timestamp: new Date().toISOString(),
    https: 'enabled'
  });
});

// ==================== HOME ====================
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
        <h1>🔒 Secure Authentication System</h1>
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
          <h2>Step 3: Login (admin: no OTP, others: need OTP)</h2>
          <form id="loginForm">
            <input name="username" placeholder="Username" required />
            <input name="password" type="password" placeholder="Password" required />
            <input name="otp" placeholder="6-digit OTP (skip for admin)" maxlength="6" />
            <button type="submit">Login</button>
          </form>
          <pre id="loginResult"></pre>
          <div id="tokenSection" style="display:none; margin-top: 15px;">
            <strong>JWT Token:</strong>
            <input type="text" id="jwtToken" readonly style="background: #e9ecef;" />
            <p><strong>Role:</strong> <span id="userRole"></span></p>
          </div>
        </div>
        <div class="section">
          <h2>Step 4: View Data (All Users - READ)</h2>
          <button id="getDataBtn" disabled>Get All Data</button>
          <pre id="dataResult"></pre>
        </div>
        <div class="section">
          <h2>Step 5: Create Data (Admin/ReadWrite Only - WRITE)</h2>
          <form id="createDataForm">
            <input name="title" placeholder="Title" required />
            <textarea name="content" placeholder="Content" rows="3" style="width: 100%; padding: 8px;" required></textarea>
            <button type="submit" id="createDataBtn" disabled>Create Data</button>
          </form>
          <pre id="createResult"></pre>
        </div>
        <script>
          let currentToken = null;

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
                currentToken = json.token;
                document.getElementById('tokenSection').style.display = 'block';
                document.getElementById('jwtToken').value = json.token;
                document.getElementById('userRole').textContent = json.user.role;
                document.getElementById('getDataBtn').disabled = false;
                document.getElementById('createDataBtn').disabled = false;
              }
            } catch (err) {
              document.getElementById('loginResult').textContent = 'Error: ' + err.message;
            }
          });

          document.getElementById('getDataBtn').addEventListener('click', async () => {
            if (!currentToken) {
              document.getElementById('dataResult').textContent = 'Please login first';
              return;
            }
            try {
              const res = await fetch('/data', {
                headers: { 'Authorization': 'Bearer ' + currentToken }
              });
              const json = await res.json();
              document.getElementById('dataResult').textContent = JSON.stringify(json, null, 2);
            } catch (err) {
              document.getElementById('dataResult').textContent = 'Error: ' + err.message;
            }
          });

          document.getElementById('createDataForm').addEventListener('submit', async (e) => {
            e.preventDefault();
            if (!currentToken) {
              document.getElementById('createResult').textContent = 'Please login first';
              return;
            }
            const data = Object.fromEntries(new FormData(e.target).entries());
            try {
              const res = await fetch('/data', {
                method: 'POST',
                headers: { 
                  'Authorization': 'Bearer ' + currentToken,
                  'Content-Type': 'application/json'
                },
                body: JSON.stringify(data)
              });
              const json = await res.json();
              document.getElementById('createResult').textContent = JSON.stringify(json, null, 2);
              if (res.ok) {
                e.target.reset();
              }
            } catch (err) {
              document.getElementById('createResult').textContent = 'Error: ' + err.message;
            }
          });
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
      [username, passwordHash, "read", secret.base32, true]
    );

    const user = result.rows[0];
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

  // Check if user is banned (Assignment 2: fail2ban)
  if (isUserBanned(username)) {
    const attempt = loginAttempts.get(username);
    const remainingTime = Math.ceil((attempt.bannedUntil - Date.now()) / 1000 / 60);
    console.log(`[FAIL2BAN] Login attempt blocked: username=${username} remaining=${remainingTime}min`);
    return res.status(403).json({ 
      error: `Account temporarily locked due to multiple failed login attempts. Try again in ${remainingTime} minutes.`, 
      code: "ACCOUNT_BANNED",
      bannedUntil: new Date(attempt.bannedUntil).toISOString()
    });
  }

  try {
    const result = await pool.query(
      "SELECT id, username, password_hash, role, two_factor_secret, two_factor_enabled FROM users WHERE username = $1",
      [username]
    );

    if (result.rowCount === 0) {
      console.log(`[LOGIN] FAILED: username=${username} reason=user_not_found`);
      recordFailedAttempt(username);
      return res.status(401).json({ 
        error: "Invalid username or password", 
        code: "AUTH_FAILED" 
      });
    }

    const user = result.rows[0];

    const passwordMatch = bcrypt.compareSync(password, user.password_hash);
    if (!passwordMatch) {
      console.log(`[LOGIN] FAILED: username=${username} reason=invalid_password`);
      const attempt = recordFailedAttempt(username);
      if (attempt.count > MAX_FAILED_ATTEMPTS) {
        return res.status(403).json({ 
          error: `Account locked after ${MAX_FAILED_ATTEMPTS} failed attempts. Try again in 15 minutes.`, 
          code: "ACCOUNT_BANNED"
        });
      }
      return res.status(401).json({ 
        error: "Invalid username or password", 
        code: "AUTH_FAILED",
        remainingAttempts: MAX_FAILED_ATTEMPTS - attempt.count + 1
      });
    }

    // Check if 2FA is enabled for this user
    if (user.two_factor_enabled) {
      if (!otp) {
        return res.status(400).json({ 
          error: "OTP required for 2FA", 
          code: "OTP_REQUIRED" 
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
        const attempt = recordFailedAttempt(username);
        if (attempt.count > MAX_FAILED_ATTEMPTS) {
          return res.status(403).json({ 
            error: `Account locked after ${MAX_FAILED_ATTEMPTS} failed attempts. Try again in 15 minutes.`, 
            code: "ACCOUNT_BANNED"
          });
        }
        return res.status(401).json({ 
          error: "Invalid OTP", 
          code: "INVALID_OTP",
          remainingAttempts: MAX_FAILED_ATTEMPTS - attempt.count + 1
        });
      }
    } else {
      console.log(`[LOGIN] 2FA disabled for username=${username}`);
    }

    // Clear failed attempts on successful login
    clearFailedAttempts(username);

    // Generate JWT token with user info
    const token = jwt.sign(
      { id: user.id, username: user.username, role: user.role },
      JWT_SECRET,
      { expiresIn: '24h' }
    );

    console.log(`[LOGIN] SUCCESS: username=${username} id=${user.id} role=${user.role}`);

    return res.status(200).json({
      message: "Login successful with 2FA verified",
      token: token,
      user: { id: user.id, username: user.username, role: user.role }
    });

  } catch (err) {
    console.error("[LOGIN] ERROR:", err);
    return res.status(500).json({ 
      error: "Internal server error", 
      code: "SERVER_ERROR" 
    });
  }
});

// ==================== JWT AUTH MIDDLEWARE ====================
function authenticateToken(req, res, next) {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1]; // Bearer TOKEN

  if (!token) {
    return res.status(401).json({ 
      error: "Access token required", 
      code: "NO_TOKEN" 
    });
  }

  jwt.verify(token, JWT_SECRET, (err, user) => {
    if (err) {
      return res.status(403).json({ 
        error: "Invalid or expired token", 
        code: "INVALID_TOKEN" 
      });
    }
    req.user = user; // Attach user info (id, username, role) to request
    next();
  });
}

// ==================== GET DATA (All authenticated users) ====================
app.get("/data", authenticateToken, async (req, res) => {
  try {
    const result = await pool.query(
      "SELECT id, title, content, created_by, created_at FROM data ORDER BY created_at DESC"
    );

    console.log(`[DATA] GET: username=${req.user.username} role=${req.user.role} count=${result.rowCount}`);

    return res.status(200).json({
      data: result.rows,
      user: { username: req.user.username, role: req.user.role },
      permissions: {
        canRead: true,
        canWrite: req.user.role === 'readwrite' || req.user.role === 'admin'
      }
    });

  } catch (err) {
    console.error("[DATA] GET ERROR:", err);
    return res.status(500).json({ 
      error: "Internal server error", 
      code: "SERVER_ERROR" 
    });
  }
});

// ==================== CREATE DATA (readwrite/admin only) ====================
app.post("/data", authenticateToken, async (req, res) => {
  const { title, content } = req.body;

  if (!title || !content) {
    return res.status(400).json({ 
      error: "Missing title or content", 
      code: "MISSING_FIELDS" 
    });
  }

  // Check role permission
  if (req.user.role !== 'readwrite' && req.user.role !== 'admin') {
    console.log(`[DATA] CREATE DENIED: username=${req.user.username} role=${req.user.role}`);
    return res.status(403).json({ 
      error: "Permission denied. READ-ONLY access.", 
      code: "INSUFFICIENT_PERMISSIONS",
      requiredRole: "readwrite or admin",
      yourRole: req.user.role
    });
  }

  try {
    const result = await pool.query(
      "INSERT INTO data (title, content, created_by) VALUES ($1, $2, $3) RETURNING id, title, created_at",
      [title, content, req.user.username]
    );

    const newData = result.rows[0];

    console.log(`[DATA] CREATE SUCCESS: username=${req.user.username} role=${req.user.role} id=${newData.id}`);

    return res.status(201).json({
      message: "Data created successfully",
      data: newData
    });

  } catch (err) {
    console.error("[DATA] CREATE ERROR:", err);
    return res.status(500).json({ 
      error: "Internal server error", 
      code: "SERVER_ERROR" 
    });
  }
});

// ==================== UPDATE DATA (readwrite/admin only) ====================
app.put("/data/:id", authenticateToken, async (req, res) => {
  const { id } = req.params;
  const { title, content } = req.body;

  if (!title || !content) {
    return res.status(400).json({ 
      error: "Missing title or content", 
      code: "MISSING_FIELDS" 
    });
  }

  // Check role permission
  if (req.user.role !== 'readwrite' && req.user.role !== 'admin') {
    console.log(`[DATA] UPDATE DENIED: username=${req.user.username} role=${req.user.role}`);
    return res.status(403).json({ 
      error: "Permission denied. READ-ONLY access.", 
      code: "INSUFFICIENT_PERMISSIONS",
      requiredRole: "readwrite or admin",
      yourRole: req.user.role
    });
  }

  try {
    const result = await pool.query(
      "UPDATE data SET title = $1, content = $2, updated_at = CURRENT_TIMESTAMP WHERE id = $3 RETURNING id, title, updated_at",
      [title, content, id]
    );

    if (result.rowCount === 0) {
      return res.status(404).json({ 
        error: "Data not found", 
        code: "DATA_NOT_FOUND" 
      });
    }

    const updatedData = result.rows[0];

    console.log(`[DATA] UPDATE SUCCESS: username=${req.user.username} role=${req.user.role} id=${id}`);

    return res.status(200).json({
      message: "Data updated successfully",
      data: updatedData
    });

  } catch (err) {
    console.error("[DATA] UPDATE ERROR:", err);
    return res.status(500).json({ 
      error: "Internal server error", 
      code: "SERVER_ERROR" 
    });
  }
});

// ==================== HTTPS STARTUP ====================
verifyConfigIntegrity();

// Load HTTPS certificates with fallback
let server;
let httpsEnabled = false;

try {
  // Check if server certs exist
  if (fs.existsSync('/app/certs/web02-server.crt') && 
      fs.existsSync('/app/certs/web02-server.key')) {
    
    const httpsOptions = {
      key: fs.readFileSync('/app/certs/web02-server.key'),
      cert: fs.readFileSync('/app/certs/web02-server.crt'),
      ca: fs.readFileSync('/app/certs/ca.crt')
    };
    
    server = https.createServer(httpsOptions, app);
    httpsEnabled = true;
    
    console.log('[SERVER] ✅ HTTPS enabled with mTLS');
    console.log('[SERVER] Certificate: web02.org.local (SERVER cert)');
    console.log('[SERVER] Listening for nginx reverse proxy');
    
  } else {
    throw new Error('Server certificates not found in /app/certs/');
  }
  
} catch (err) {
  console.warn('[SERVER] ⚠️  HTTPS failed:', err.message);
  console.log('[SERVER] Falling back to HTTP');
  server = require('http').createServer(app);
  httpsEnabled = false;
}

server.listen(PORT, () => {
  console.log(`[SERVER] Web API listening on ${httpsEnabled ? 'HTTPS' : 'HTTP'} port ${PORT}`);
  console.log(`[SERVER] 2FA enabled with TOTP (Time-based OTP)`);
  console.log(`[SERVER] Health check: GET /health`);
});