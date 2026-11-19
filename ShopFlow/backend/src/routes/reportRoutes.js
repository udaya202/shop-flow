import express from "express";
import { authenticate } from "../middleware/authMiddleware.js";
import { allowRoles } from "../middleware/roleMiddleware.js";
import { getReportSummary, createExpense } from "../controllers/reportController.js";
const router = express.Router();
router.use(authenticate, allowRoles("owner", "manager"));
router.get("/summary", getReportSummary);
router.post("/expenses", createExpense);
export default router;
