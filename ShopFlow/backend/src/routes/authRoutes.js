import express from "express";
import rateLimit from "express-rate-limit";

import { registerShop } from "../controllers/authController.js";
import {
  sessionLogin,
  refreshSession,
  sessionLogout
} from "../controllers/sessionController.js";

const router = express.Router();

// Public signup is intentionally open, but limit repeated attempts from one IP.
const registrationLimiter = rateLimit({
  windowMs: 60 * 60 * 1000,
  limit: 10,
  standardHeaders: true,
  legacyHeaders: false,
  message: {
    success: false,
    message: "Too many registration attempts. Please try again later."
  }
});

router.post("/register", registrationLimiter, registerShop);
router.post("/login", sessionLogin);
router.post("/refresh", refreshSession);
router.post("/logout", sessionLogout);

export default router;
