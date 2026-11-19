import mongoose from "mongoose";

const superAdminSchema = new mongoose.Schema({
  name: { type: String, required: true, trim: true, maxlength: 120 },
  email: { type: String, required: true, lowercase: true, trim: true, maxlength: 254, unique: true },
  passwordHash: { type: String, required: true, select: false },
  status: { type: String, enum: ["active", "disabled"], default: "active", index: true },
  lastLoginAt: { type: Date, default: null }
}, { timestamps: true });

export default mongoose.model("SuperAdmin", superAdminSchema);
