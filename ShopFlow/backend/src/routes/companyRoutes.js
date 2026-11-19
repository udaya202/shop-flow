import express from "express";
import { authenticate } from "../middleware/authMiddleware.js";
import { allowRoles } from "../middleware/roleMiddleware.js";
import {
  getCompanySettings,
  updateCompanySettings
} from "../controllers/companyController.js";

const router = express.Router();
router.use(authenticate, allowRoles("owner"));
router.get("/", getCompanySettings);
router.put("/", updateCompanySettings);

export default router;
