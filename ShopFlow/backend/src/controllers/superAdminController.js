import jwt from "jsonwebtoken";
import argon2 from "argon2";
import mongoose from "mongoose";
import SuperAdmin from "../models/SuperAdmin.js";
import Tenant from "../models/Tenant.js";
import User from "../models/UserModel.js";
import Product from "../models/ProductModel.js";
import Sale from "../models/SaleModel.js";

const safeAdmin = (admin) => ({
  id: admin._id,
  name: admin.name,
  email: admin.email,
  lastLoginAt: admin.lastLoginAt
});

export async function superAdminLogin(req, res) {
  try {
    const email = String(req.body?.email ?? "").trim().toLowerCase();
    const password = String(req.body?.password ?? "");

    if (!email || !password) {
      return res.status(400).json({ success: false, message: "Email and password are required" });
    }

    const admin = await SuperAdmin.findOne({ email, status: "active" }).select("+passwordHash");
    if (!admin || !(await argon2.verify(admin.passwordHash, password))) {
      return res.status(401).json({ success: false, message: "Invalid login details" });
    }

    admin.lastLoginAt = new Date();
    await admin.save();

    const accessToken = jwt.sign(
      { superAdminId: admin._id.toString(), tokenType: "super_admin" },
      process.env.JWT_ACCESS_SECRET,
      { expiresIn: "15m", issuer: "shopflow", audience: "shopflow-super-admin" }
    );

    return res.json({
      success: true,
      message: "Super Admin login successful",
      data: { accessToken, admin: safeAdmin(admin) }
    });
  } catch (error) {
    console.error("Super Admin login error:", error);
    return res.status(500).json({ success: false, message: "Unable to login" });
  }
}

export async function getSuperAdminMe(req, res) {
  const admin = await SuperAdmin.findById(req.superAdmin.id).select("_id name email lastLoginAt");
  return res.json({ success: true, data: { admin: safeAdmin(admin) } });
}

export async function getPlatformOverview(req, res) {
  try {
    const [
      totalShops, activeShops, suspendedShops, totalOwners,
      totalUsers, totalProducts, totalSales, salesAggregate
    ] = await Promise.all([
      Tenant.countDocuments({}),
      Tenant.countDocuments({ status: "active" }),
      Tenant.countDocuments({ status: "suspended" }),
      User.countDocuments({ role: "owner" }),
      User.countDocuments({}),
      Product.countDocuments({}),
      Sale.countDocuments({}),
      Sale.aggregate([{ $group: { _id: null, revenue: { $sum: "$totalAmount" } } }])
    ]);

    return res.json({
      success: true,
      data: {
        totalShops, activeShops, suspendedShops, totalOwners,
        totalUsers, totalProducts, totalSales,
        totalRevenue: Math.round((salesAggregate[0]?.revenue || 0) * 100) / 100
      }
    });
  } catch (error) {
    console.error("Platform overview error:", error);
    return res.status(500).json({ success: false, message: "Unable to load platform overview" });
  }
}

export async function getPlatformShops(req, res) {
  try {
    const page = Math.max(1, Number(req.query.page) || 1);
    const limit = Math.min(100, Math.max(1, Number(req.query.limit) || 20));
    const search = String(req.query.search ?? "").trim();
    const filter = {};

    if (["active", "suspended"].includes(req.query.status)) filter.status = req.query.status;
    if (search) {
      const escaped = search.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      filter.$or = [
        { shopName: { $regex: escaped, $options: "i" } },
        { email: { $regex: escaped, $options: "i" } },
        { slug: { $regex: escaped, $options: "i" } }
      ];
    }

    const [shops, total] = await Promise.all([
      Tenant.find(filter).sort({ createdAt: -1 }).skip((page - 1) * limit).limit(limit).lean(),
      Tenant.countDocuments(filter)
    ]);

    const ids = shops.map(shop => shop._id);
    const owners = await User.find({ tenantId: { $in: ids }, role: "owner" })
      .select("tenantId name email status").lean();
    const ownerMap = new Map(owners.map(owner => [owner.tenantId.toString(), owner]));

    const data = shops.map(shop => ({
      id: shop._id,
      shopName: shop.shopName,
      slug: shop.slug,
      email: shop.email,
      phone: shop.phone,
      businessType: shop.businessType,
      status: shop.status,
      createdAt: shop.createdAt,
      owner: ownerMap.get(shop._id.toString()) || null
    }));

    return res.json({
      success: true, data,
      pagination: { page, limit, total, pages: Math.ceil(total / limit) }
    });
  } catch (error) {
    console.error("Platform shops error:", error);
    return res.status(500).json({ success: false, message: "Unable to load shops" });
  }
}

export async function updateShopStatus(req, res) {
  try {
    if (!mongoose.Types.ObjectId.isValid(req.params.shopId)) {
      return res.status(400).json({ success: false, message: "Invalid shop ID" });
    }
    const status = String(req.body?.status ?? "");
    if (!["active", "suspended"].includes(status)) {
      return res.status(400).json({ success: false, message: "Status must be active or suspended" });
    }

    const shop = await Tenant.findByIdAndUpdate(
      req.params.shopId, { $set: { status } }, { new: true, runValidators: true }
    ).select("_id shopName slug status");

    if (!shop) return res.status(404).json({ success: false, message: "Shop not found" });
    return res.json({ success: true, message: `Shop ${status}`, data: shop });
  } catch (error) {
    console.error("Update shop status error:", error);
    return res.status(500).json({ success: false, message: "Unable to update shop status" });
  }
}

export async function getPlatformOwners(req, res) {
  try {
    const page = Math.max(1, Number(req.query.page) || 1);
    const limit = Math.min(100, Math.max(1, Number(req.query.limit) || 20));
    const search = String(req.query.search ?? "").trim();
    const filter = { role: "owner" };
    if (search) {
      const escaped = search.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      filter.$or = [
        { name: { $regex: escaped, $options: "i" } },
        { email: { $regex: escaped, $options: "i" } }
      ];
    }

    const [owners, total] = await Promise.all([
      User.find(filter).select("tenantId name email role status createdAt").sort({ createdAt: -1 })
        .skip((page - 1) * limit).limit(limit).lean(),
      User.countDocuments(filter)
    ]);
    const tenantIds = owners.map(owner => owner.tenantId);
    const tenants = await Tenant.find({ _id: { $in: tenantIds } }).select("shopName slug status").lean();
    const tenantMap = new Map(tenants.map(tenant => [tenant._id.toString(), tenant]));

    return res.json({
      success: true,
      data: owners.map(owner => ({
        id: owner._id, name: owner.name, email: owner.email, status: owner.status,
        createdAt: owner.createdAt,
        shop: tenantMap.get(owner.tenantId.toString()) || null
      })),
      pagination: { page, limit, total, pages: Math.ceil(total / limit) }
    });
  } catch (error) {
    console.error("Platform owners error:", error);
    return res.status(500).json({ success: false, message: "Unable to load owners" });
  }
}
