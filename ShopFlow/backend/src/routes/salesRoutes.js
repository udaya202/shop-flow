
import express from "express";

import { authenticate } from "../middleware/authMiddleware.js";

import {
  createSale,
  getSales,
  getSaleById
} from "../controllers/salesController.js";

const router = express.Router();

// Every POS endpoint requires authentication.
router.use(authenticate);

// Create a new sale.
router.post("/", createSale);

// View sales history.
router.get("/", getSales);

// View one invoice.
router.get("/:id", getSaleById);

export default router;
