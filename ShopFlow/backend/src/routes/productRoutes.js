
import express from "express";

import { authenticate } from "../middleware/authMiddleware.js";
import { allowRoles } from "../middleware/roleMiddleware.js";

import {
  createProduct,
  getProducts,
  getProductById,
  updateProduct,
  deleteProduct,
  getLowStockProducts
} from "../controllers/productController.js";

const router = express.Router();

// All product routes require authentication.
router.use(authenticate);

// Low stock must come before /:id.
router.get("/low-stock", getLowStockProducts);

router.post("/", allowRoles("owner", "manager"), createProduct);
router.get("/", getProducts);
router.get("/:id", getProductById);
router.put("/:id", allowRoles("owner", "manager"), updateProduct);
router.delete("/:id", allowRoles("owner", "manager"), deleteProduct);

export default router;
