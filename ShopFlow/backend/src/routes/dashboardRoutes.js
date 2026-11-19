import express from "express";
import mongoose from "mongoose";
import { authenticate } from "../middleware/authMiddleware.js";
import Product from "../models/ProductModel.js";
import Customer from "../models/CustomerModel.js";
import Sale from "../models/SaleModel.js";

const router = express.Router();

router.get("/summary", authenticate, async (req, res) => {
  try {
    // Tenant scope always comes from the authenticated user.
    const tenantId = new mongoose.Types.ObjectId(req.user.tenantId);

    const now = new Date();
    const todayStart = new Date(Date.UTC(
      now.getUTCFullYear(),
      now.getUTCMonth(),
      now.getUTCDate(),
    ));
    const tomorrowStart = new Date(todayStart.getTime() + 86400000);
    const weekStart = new Date(todayStart.getTime() - 6 * 86400000);

    const [
      totalProducts,
      totalCustomers,
      lowStockCount,
      todaySalesAggregate,
      weeklySalesAggregate,
      recentSales,
    ] = await Promise.all([
      Product.countDocuments({ tenantId, isActive: true }),
      Customer.countDocuments({ tenantId, isActive: true }),
      Product.countDocuments({
        tenantId,
        isActive: true,
        $expr: { $lte: ["$stockQuantity", "$minStockLevel"] },
      }),
      Sale.aggregate([
        {
          $match: {
            tenantId,
            createdAt: { $gte: todayStart, $lt: tomorrowStart },
          },
        },
        {
          $group: {
            _id: null,
            revenue: { $sum: "$totalAmount" },
            invoiceCount: { $sum: 1 },
          },
        },
      ]),
      Sale.aggregate([
        {
          $match: {
            tenantId,
            createdAt: { $gte: weekStart, $lt: tomorrowStart },
          },
        },
        {
          $group: {
            _id: {
              $dateToString: {
                format: "%Y-%m-%d",
                date: "$createdAt",
                timezone: "UTC",
              },
            },
            revenue: { $sum: "$totalAmount" },
            invoiceCount: { $sum: 1 },
          },
        },
        { $sort: { _id: 1 } },
      ]),
      Sale.find({ tenantId })
        .select("invoiceNumber customerSnapshot totalAmount paymentStatus createdAt")
        .sort({ createdAt: -1 })
        .limit(5)
        .lean(),
    ]);

    const today = todaySalesAggregate[0] || {
      revenue: 0,
      invoiceCount: 0,
    };

    const weeklyByDate = new Map(
      weeklySalesAggregate.map((item) => [
        item._id,
        {
          date: item._id,
          revenue: Math.round(item.revenue * 100) / 100,
          invoiceCount: item.invoiceCount,
        },
      ]),
    );

    const weeklySales = [];
    for (
      let day = new Date(weekStart);
      day < tomorrowStart;
      day.setUTCDate(day.getUTCDate() + 1)
    ) {
      const date = day.toISOString().slice(0, 10);
      weeklySales.push(
        weeklyByDate.get(date) || {
          date,
          revenue: 0,
          invoiceCount: 0,
        },
      );
    }

    return res.json({
      success: true,
      data: {
        totalProducts,
        totalCustomers,
        lowStockCount,
        todayRevenue: Math.round(today.revenue * 100) / 100,
        todayInvoiceCount: today.invoiceCount,
        weeklySales,
        recentSales,
      },
    });
  } catch (error) {
    console.error("Dashboard summary error:", error);
    return res.status(500).json({
      success: false,
      message: "Unable to load dashboard summary",
    });
  }
});

export default router;
