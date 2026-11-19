import mongoose from "mongoose";

const customerSchema = new mongoose.Schema(
  {
    tenantId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "Tenant",
      required: true,
      index: true
    },
    name: { type: String, required: true, trim: true, maxlength: 120 },
    phone: { type: String, default: "", trim: true, maxlength: 40 },
    email: { type: String, default: "", trim: true, lowercase: true, maxlength: 180 },
    address: { type: String, default: "", trim: true, maxlength: 500 },
    notes: { type: String, default: "", trim: true, maxlength: 1000 },
    isActive: { type: Boolean, default: true }
  },
  { timestamps: true }
);

customerSchema.index({ tenantId: 1, name: 1 });
customerSchema.index({ tenantId: 1, phone: 1 });

export default mongoose.model("Customer", customerSchema);
