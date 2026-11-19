import mongoose from "mongoose";

const tenantSchema = new mongoose.Schema(
  {
    shopName: { type: String, required: true, trim: true },
    slug: {
      type: String, required: true, unique: true,
      lowercase: true, trim: true
    },
    email: { type: String, required: true, lowercase: true, trim: true },
    phone: { type: String, default: "" },
    businessType: { type: String, default: "general" },

    // Company profile fields (kept on the tenant to isolate each shop).
    address: { type: String, default: "", maxlength: 500 },
    logoUrl: { type: String, default: "", maxlength: 2000 },
    website: { type: String, default: "", maxlength: 300 },

    status: { type: String, enum: ["active", "suspended"], default: "active" }
  },
  { timestamps: true }
);

export default mongoose.model("Tenant", tenantSchema);
