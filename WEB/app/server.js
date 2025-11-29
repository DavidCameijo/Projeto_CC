const readline = require("readline");
const axios = require("axios");

const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout
});

let token = null;
let username = null;

async function showMenu() {
  console.log("\n=== Web API CLI Client ===");
  console.log("1. Login");
  console.log("2. Health check");
  console.log("3. List feriados");
  console.log("4. Add feriado (admin only)");
  console.log("5. Logout");
  console.log("0. Exit");
  
  rl.question("Choose option: ", handleChoice);
}

async function handleChoice(choice) {
  try {
    switch (choice) {
      case "1": await login(); break;
      case "2": await healthCheck(); break;
      case "3": await listFeriados(); break;
      case "4": await addFeriado(); break;
      case "5":
        token = null;
        username = null;
        console.log("Logged out.");
        break;
      case "0":
        console.log("Goodbye!");
        rl.close();
        return;
      default:
        console.log("Invalid option.");
    }
  } catch (err) {
    console.error("Error:", err.message);
  }
  showMenu();
}

async function login() {
  rl.question("Username: ", async (user) => {
    rl.question("Password: ", async (pass) => {
      try {
        const response = await axios.post("http://127.0.0.1:3000/login", {
          username: user,
          password: pass
        });
        
        token = response.data.token;
        username = response.data.username;
        console.log(`✅ Login successful! Role: ${response.data.role}`);
      } catch (err) {
        console.log(`❌ ${err.response?.data?.error || err.message}`);
      }
    });
  });
}

async function healthCheck() {
  try {
    const response = await axios.get("http://127.0.0.1:3000/health");
    console.log("Health:", response.data.status);
  } catch (err) {
    console.log(`❌ ${err.message}`);
  }
}

async function listFeriados() {
  if (!token) return console.log("❌ Please login first");
  
  try {
    const response = await axios.get("http://127.0.0.1:3000/feriados", {
      headers: { Authorization: `Bearer ${token}` }
    });
    
    console.log("\nFeriados:");
    response.data.forEach(f => {
      console.log(`  ${f.label}`);
    });
  } catch (err) {
    console.log(`❌ ${err.response?.data?.error || err.message}`);
  }
}

async function addFeriado() {
  if (!token) return console.log("❌ Please login first");
  
  rl.question("Day (1-31): ", (day) => {
    rl.question("Month (1-12): ", (month) => {
      rl.question("Description: ", async (desc) => {
        try {
          const response = await axios.post("http://127.0.0.1:3000/feriados", {
            day: parseInt(day),
            month: parseInt(month),
            description: desc
          }, {
            headers: { 
              Authorization: `Bearer ${token}`,
              "Content-Type": "application/json"
            }
          });
          
          console.log(`✅ Added: ${response.data.label}`);
        } catch (err) {
          console.log(`❌ ${err.response?.data?.error || err.message}`);
        }
      });
    });
  });
}

console.log("Connect to web01 API...");
showMenu();
