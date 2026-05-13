const express = require("express");
const axios = require("axios");
const path = require("path");
const { v4: uuidv4 } = require("uuid");

const app = express();
const PORT = process.env.PORT || 3000;
const BACKEND_URL = process.env.BACKEND_URL || "http://backend:5000";

app.use(express.json());
app.use(express.static(path.join(__dirname, "public")));

// Proxy all /api/* requests to the backend service
app.use("/api", async (req, res) => {
  const url = `${BACKEND_URL}/api${req.path}`;
  try {
    const response = await axios({
      method: req.method,
      url,
      data: req.body,
      params: req.query,
      headers: { "Content-Type": "application/json" },
      timeout: 10000,
    });
    res.status(response.status).json(response.data);
  } catch (err) {
    const status = err.response?.status || 502;
    const data = err.response?.data || { error: err.message };
    res.status(status).json(data);
  }
});

app.get("/health", (_req, res) => {
  res.json({ status: "healthy", service: "frontend", backendUrl: BACKEND_URL });
});

// All other routes serve the SPA
app.get("*", (_req, res) => {
  res.sendFile(path.join(__dirname, "public", "index.html"));
});

app.listen(PORT, () => {
  console.log(`ShopNow frontend running on http://0.0.0.0:${PORT}`);
  console.log(`Proxying API requests to ${BACKEND_URL}`);
});
