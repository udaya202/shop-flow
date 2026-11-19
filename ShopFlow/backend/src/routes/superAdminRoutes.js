import express from "express";
import rateLimit from "express-rate-limit";
import { authenticateSuperAdmin } from "../middleware/superAdminMiddleware.js";
import {
  superAdminLogin, getSuperAdminMe, getPlatformOverview,
  getPlatformShops, updateShopStatus, getPlatformOwners
} from "../controllers/superAdminController.js";

const router = express.Router();

const loginLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: 8,
  standardHeaders: true,
  legacyHeaders: false,
  message: { success: false, message: "Too many login attempts. Try again later." }
});

router.post("/auth/login", loginLimiter, superAdminLogin);
router.use(authenticateSuperAdmin);
router.get("/auth/me", getSuperAdminMe);
router.get("/overview", getPlatformOverview);
router.get("/shops", getPlatformShops);
router.patch("/shops/:shopId/status", updateShopStatus);
router.get("/owners", getPlatformOwners);

export default router;
