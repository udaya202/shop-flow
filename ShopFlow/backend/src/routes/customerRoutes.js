import express from "express";
import { authenticate } from "../middleware/authMiddleware.js";
import {
  getCustomers,
  createCustomer,
  updateCustomer,
  deleteCustomer,
  getCustomerSales
} from "../controllers/customerController.js";

const router = express.Router();
router.use(authenticate);

router.get("/", getCustomers);
router.post("/", createCustomer);
router.get("/:id/sales", getCustomerSales);
router.put("/:id", updateCustomer);
router.delete("/:id", deleteCustomer);

export default router;
