
import express from "express";

import {
  registerShop
} from "../controllers/authController.js";

import {
  sessionLogin,
  refreshSession,
  sessionLogout
} from "../controllers/sessionController.js";

const router = express.Router();

router.post("/register", registerShop);

router.post("/login", sessionLogin);

router.post("/refresh", refreshSession);

router.post("/logout", sessionLogout);

export default router;
