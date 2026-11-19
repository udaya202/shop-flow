import mongoose from "mongoose";
import Sale from "../models/SaleModel.js";
import Expense from "../models/ExpenseModel.js";

function periodRange(period, dateInput) {
  const base = dateInput ? new Date(`${dateInput}T00:00:00.000Z`) : new Date();
  if (Number.isNaN(base.getTime())) throw new Error("Invalid report date");
  const start = new Date(Date.UTC(base.getUTCFullYear(), base.getUTCMonth(), base.getUTCDate()));
  let end;
  if (period === "daily") end = new Date(start.getTime() + 86400000);
  else if (period === "weekly") { const day = (start.getUTCDay() + 6) % 7; start.setUTCDate(start.getUTCDate() - day); end = new Date(start.getTime() + 7 * 86400000); }
  else if (period === "monthly") { start.setUTCDate(1); end = new Date(Date.UTC(start.getUTCFullYear(), start.getUTCMonth() + 1, 1)); }
  else throw new Error("Period must be daily, weekly or monthly");
  return { start, end };
}

export async function getReportSummary(req, res) {
  try {
    const period = String(req.query.period || "daily");
    const { start, end } = periodRange(period, req.query.date);
    const tenantId = new mongoose.Types.ObjectId(req.user.tenantId);
    const dateFilter = { tenantId, createdAt: { $gte: start, $lt: end } };
    const expenseFilter = { tenantId, expenseDate: { $gte: start, $lt: end } };
    const [salesAgg, expensesAgg, expenses, sales] = await Promise.all([
      Sale.aggregate([
        { $match: dateFilter },
        { $project: {
          revenue: { $sum: "$items.lineTotal" },
          cost: { $sum: { $map: { input: "$items", as: "item", in: { $multiply: ["$$item.purchasePrice", "$$item.quantity"] } } } },
          units: { $sum: { $map: { input: "$items", as: "item", in: "$$item.quantity" } } },
          discount: { $ifNull: ["$discountAmount", 0] }
        } },
        { $group: { _id: null, revenue: { $sum: "$revenue" }, cost: { $sum: "$cost" }, units: { $sum: "$units" }, invoiceCount: { $sum: 1 }, discounts: { $sum: "$discount" } } },
        { $project: { revenue: 1, cost: 1, units: 1, invoiceCount: 1, discounts: 1, grossProfit: { $subtract: [{ $subtract: ["$revenue", "$cost"] }, "$discounts"] } } }
      ]),
      Expense.aggregate([{ $match: expenseFilter }, { $group: { _id: null, total: { $sum: "$amount" }, count: { $sum: 1 } } }]),
      Expense.find(expenseFilter).sort({ expenseDate: -1 }).limit(100).lean(),
      Sale.find(dateFilter).select("invoiceNumber totalAmount createdAt").sort({ createdAt: -1 }).limit(100).lean()
    ]);
    const s = salesAgg[0] || { revenue: 0, cost: 0, units: 0, invoiceCount: 0, discounts: 0, grossProfit: 0 };
    const e = expensesAgg[0] || { total: 0, count: 0 };
    const expenseTotal = Math.round(e.total * 100) / 100;
    return res.json({ success: true, data: { period, startDate: start, endDate: end, revenue: Math.round(s.revenue * 100) / 100, costOfGoods: Math.round(s.cost * 100) / 100, discounts: Math.round(s.discounts * 100) / 100, grossProfit: Math.round(s.grossProfit * 100) / 100, expenses: expenseTotal, netProfit: Math.round((s.grossProfit - expenseTotal) * 100) / 100, invoiceCount: s.invoiceCount, unitsSold: s.units, expenseCount: e.count, expenseItems: expenses, recentSales: sales } });
  } catch (error) {
    console.error("Report summary error:", error);
    return res.status(400).json({ success: false, message: error.message || "Unable to generate report" });
  }
}

export async function createExpense(req, res) {
  try {
    const title = String(req.body.title || "").trim();
    const amount = Number(req.body.amount);
    const category = String(req.body.category || "General").trim();
    const expenseDate = req.body.expenseDate ? new Date(req.body.expenseDate) : new Date();
    if (!title || !Number.isFinite(amount) || amount <= 0 || Number.isNaN(expenseDate.getTime())) return res.status(400).json({ success: false, message: "Enter a valid title, amount and date" });
    const expense = await Expense.create({ tenantId: req.user.tenantId, title, amount: Math.round(amount * 100) / 100, category, expenseDate, note: String(req.body.note || "").trim(), createdBy: req.user.id });
    return res.status(201).json({ success: true, message: "Expense saved", data: expense });
  } catch (error) {
    console.error("Create expense error:", error);
    return res.status(500).json({ success: false, message: "Unable to save expense" });
  }
}
