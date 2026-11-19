
import jwt from "jsonwebtoken";
import User from "../models/UserModel.js";
import Tenant from "../models/Tenant.js";

export async function authenticate(req, res, next) {
  try {
    const authHeader = req.headers.authorization;

    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      return res.status(401).json({
        success: false,
        message: "Authentication required"
      });
    }

    const token = authHeader.split(" ")[1];

    const decoded = jwt.verify(
      token,
      process.env.JWT_ACCESS_SECRET
    );

    const user = await User.findOne({
      _id: decoded.userId,
      tenantId: decoded.tenantId,
      status: "active"
    });

    if (!user) {
      return res.status(401).json({
        success: false,
        message: "User account not found or disabled"
      });
    }

    const tenant = await Tenant.findOne({
      _id: decoded.tenantId,
      status: "active"
    });

    if (!tenant) {
      return res.status(401).json({
        success: false,
        message: "Shop is inactive"
      });
    }

    req.user = {
      id: user._id.toString(),
      tenantId: tenant._id.toString(),
      role: user.role,
      name: user.name
    };

    next();

  } catch (error) {
    return res.status(401).json({
      success: false,
      message: "Invalid or expired token"
    });
  }
}
