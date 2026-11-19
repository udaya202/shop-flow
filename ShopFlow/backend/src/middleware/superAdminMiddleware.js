import jwt from "jsonwebtoken";
import SuperAdmin from "../models/SuperAdmin.js";

export async function authenticateSuperAdmin(req, res, next) {
  try {
    const header = req.headers.authorization || "";
    if (!header.startsWith("Bearer ")) {
      return res.status(401).json({ success: false, message: "Super Admin authentication required" });
    }

    const token = header.slice(7);
    const decoded = jwt.verify(token, process.env.JWT_ACCESS_SECRET, {
      issuer: "shopflow",
      audience: "shopflow-super-admin"
    });

    if (decoded.tokenType !== "super_admin" || !decoded.superAdminId) {
      return res.status(401).json({ success: false, message: "Invalid Super Admin token" });
    }

    const admin = await SuperAdmin.findOne({
      _id: decoded.superAdminId,
      status: "active"
    }).select("_id name email status");

    if (!admin) {
      return res.status(401).json({ success: false, message: "Super Admin account unavailable" });
    }

    req.superAdmin = {
      id: admin._id.toString(),
      name: admin.name,
      email: admin.email
    };
    next();
  } catch {
    return res.status(401).json({ success: false, message: "Invalid or expired Super Admin token" });
  }
}
