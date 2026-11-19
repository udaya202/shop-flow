import mongoose from "mongoose";
const expenseSchema = new mongoose.Schema({
  tenantId: { type: mongoose.Schema.Types.ObjectId, ref: "Tenant", required: true, index: true },
  title: { type: String, required: true, trim: true, maxlength: 120 },
  category: { type: String, default: "General", trim: true, maxlength: 60 },
  amount: { type: Number, required: true, min: 0.01 },
  expenseDate: { type: Date, required: true, default: Date.now },
  note: { type: String, default: "", maxlength: 500 },
  createdBy: { type: mongoose.Schema.Types.ObjectId, ref: "User", required: true }
}, { timestamps: true });
expenseSchema.index({ tenantId: 1, expenseDate: -1 });
export default mongoose.model("Expense", expenseSchema);
