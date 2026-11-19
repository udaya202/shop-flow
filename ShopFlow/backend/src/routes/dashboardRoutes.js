
import express from "express";
import { authenticate } from "../middleware/authMiddleware.js";

const router = express.Router();

router.get("/", authenticate, (req, res) => {
  res.json({
    success: true,
    message: "Welcome to ShopFlow Dashboard",
    user: req.user
  });
});

export default router;
