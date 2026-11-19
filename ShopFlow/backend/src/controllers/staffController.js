import mongoose from "mongoose";
import argon2 from "argon2";
import User from "../models/UserModel.js";

const STAFF_ROLES = ["manager", "cashier"];
const safeUser = user => ({ id: user._id, name: user.name, email: user.email, role: user.role, status: user.status, createdAt: user.createdAt });

export async function getStaff(req, res) {
  try {
    const users = await User.find({ tenantId: req.user.tenantId, role: { $in: STAFF_ROLES } }).sort({ createdAt: -1 }).lean();
    return res.json({ success: true, data: users.map(safeUser) });
  } catch (error) {
    console.error("Get staff error:", error);
    return res.status(500).json({ success: false, message: "Unable to load staff" });
  }
}

export async function createStaff(req, res) {
  try {
    const name = String(req.body.name || "").trim();
    const email = String(req.body.email || "").trim().toLowerCase();
    const password = String(req.body.password || "");
    const role = String(req.body.role || "cashier");
    if (!name || !email || !password) return res.status(400).json({ success: false, message: "Name, email and password are required" });
    if (password.length < 8) return res.status(400).json({ success: false, message: "Password must contain at least 8 characters" });
    if (!STAFF_ROLES.includes(role)) return res.status(400).json({ success: false, message: "Only Manager or Cashier roles can be created" });
    const existing = await User.findOne({ tenantId: req.user.tenantId, email }).lean();
    if (existing) return res.status(409).json({ success: false, message: "This email is already used in your shop" });
    const user = await User.create({ tenantId: req.user.tenantId, name, email, passwordHash: await argon2.hash(password), role, status: "active" });
    return res.status(201).json({ success: true, message: "Staff account created", data: safeUser(user) });
  } catch (error) {
    console.error("Create staff error:", error);
    return res.status(500).json({ success: false, message: "Unable to create staff account" });
  }
}

export async function updateStaff(req, res) {
  try {
    if (!mongoose.Types.ObjectId.isValid(req.params.id)) return res.status(400).json({ success: false, message: "Invalid staff ID" });
    const user = await User.findOne({ _id: req.params.id, tenantId: req.user.tenantId, role: { $in: STAFF_ROLES } }).select("+passwordHash");
    if (!user) return res.status(404).json({ success: false, message: "Staff member not found" });
    const { name, email, role, status, password } = req.body;
    if (name !== undefined) { const v = String(name).trim(); if (!v) return res.status(400).json({ success: false, message: "Name is required" }); user.name = v; }
    if (email !== undefined) user.email = String(email).trim().toLowerCase();
    if (role !== undefined) { if (!STAFF_ROLES.includes(role)) return res.status(400).json({ success: false, message: "Invalid staff role" }); user.role = role; }
    if (status !== undefined) { if (!["active", "disabled"].includes(status)) return res.status(400).json({ success: false, message: "Invalid status" }); user.status = status; }
    if (password !== undefined && String(password).length > 0) { if (String(password).length < 8) return res.status(400).json({ success: false, message: "Password must contain at least 8 characters" }); user.passwordHash = await argon2.hash(String(password)); }
    await user.save();
    return res.json({ success: true, message: "Staff account updated", data: safeUser(user) });
  } catch (error) {
    if (error.code === 11000) return res.status(409).json({ success: false, message: "Email is already used in this shop" });
    console.error("Update staff error:", error);
    return res.status(500).json({ success: false, message: "Unable to update staff account" });
  }
}

export async function disableStaff(req, res) {
  try {
    if (!mongoose.Types.ObjectId.isValid(req.params.id)) return res.status(400).json({ success: false, message: "Invalid staff ID" });
    const user = await User.findOneAndUpdate({ _id: req.params.id, tenantId: req.user.tenantId, role: { $in: STAFF_ROLES } }, { $set: { status: "disabled" } }, { new: true });
    if (!user) return res.status(404).json({ success: false, message: "Staff member not found" });
    return res.json({ success: true, message: "Staff account disabled" });
  } catch (error) {
    console.error("Disable staff error:", error);
    return res.status(500).json({ success: false, message: "Unable to disable staff account" });
  }
}
