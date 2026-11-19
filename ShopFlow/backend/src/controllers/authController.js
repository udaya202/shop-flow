
import Tenant from "../models/Tenant.js";
import User from "../models/UserModel.js";
import argon2 from "argon2";
import jwt from "jsonwebtoken";

// SHOP REGISTRATION
export async function registerShop(req, res) {
  try {
    const {
      shopName,
      ownerName,
      email,
      phone,
      password,
      businessType
    } = req.body;

    if (!shopName || !ownerName || !email || !password) {
      return res.status(400).json({
        success: false,
        message: "Required fields are missing"
      });
    }

    if (password.length < 8) {
      return res.status(400).json({
        success: false,
        message: "Password must contain at least 8 characters"
      });
    }

    const normalizedEmail = email.trim().toLowerCase();

    const existingUser = await User.findOne({
      email: normalizedEmail
    });

    if (existingUser) {
      return res.status(409).json({
        success: false,
        message: "Email already registered"
      });
    }

    const baseSlug = shopName
      .toLowerCase()
      .trim()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-|-$/g, "");

    if (!baseSlug) {
      return res.status(400).json({
        success: false,
        message: "Invalid shop name"
      });
    }

    const slug = `${baseSlug}-${Date.now()}`;
    const passwordHash = await argon2.hash(password);

    const tenant = new Tenant({
      shopName: shopName.trim(),
      slug,
      email: normalizedEmail,
      phone: phone || "",
      businessType: businessType || "general"
    });

    const user = new User({
      tenantId: tenant._id,
      name: ownerName.trim(),
      email: normalizedEmail,
      passwordHash,
      role: "owner"
    });

    await tenant.save();

    try {
      await user.save();
    } catch (error) {
      await Tenant.deleteOne({ _id: tenant._id });
      throw error;
    }

    const accessToken = jwt.sign(
      {
        userId: user._id.toString(),
        tenantId: tenant._id.toString(),
        role: user.role
      },
      process.env.JWT_ACCESS_SECRET,
      { expiresIn: "15m" }
    );

    return res.status(201).json({
      success: true,
      message: "Shop registered successfully",
      data: {
        shop: {
          id: tenant._id,
          shopName: tenant.shopName,
          slug: tenant.slug
        },
        user: {
          id: user._id,
          name: user.name,
          email: user.email,
          role: user.role
        },
        accessToken
      }
    });

  } catch (error) {
    console.error("Registration error:", error);

    return res.status(500).json({
      success: false,
      message: "Registration failed"
    });
  }
}

// OWNER / STAFF LOGIN
export async function login(req, res) {
  try {
    const { shopSlug, email, password } = req.body;

    if (!shopSlug || !email || !password) {
      return res.status(400).json({
        success: false,
        message: "Shop, email and password are required"
      });
    }

    const tenant = await Tenant.findOne({
      slug: shopSlug.trim().toLowerCase(),
      status: "active"
    });

    if (!tenant) {
      return res.status(401).json({
        success: false,
        message: "Invalid login details"
      });
    }

    const user = await User.findOne({
      tenantId: tenant._id,
      email: email.trim().toLowerCase(),
      status: "active"
    }).select("+passwordHash");

    if (!user) {
      return res.status(401).json({
        success: false,
        message: "Invalid login details"
      });
    }

    const validPassword = await argon2.verify(
      user.passwordHash,
      password
    );

    if (!validPassword) {
      return res.status(401).json({
        success: false,
        message: "Invalid login details"
      });
    }

    const accessToken = jwt.sign(
      {
        userId: user._id.toString(),
        tenantId: tenant._id.toString(),
        role: user.role
      },
      process.env.JWT_ACCESS_SECRET,
      { expiresIn: "15m" }
    );

    return res.status(200).json({
      success: true,
      message: "Login successful",
      data: {
        shop: {
          id: tenant._id,
          shopName: tenant.shopName,
          slug: tenant.slug
        },
        user: {
          id: user._id,
          name: user.name,
          email: user.email,
          role: user.role
        },
        accessToken
      }
    });

  } catch (error) {
    console.error("Login error:", error);

    return res.status(500).json({
      success: false,
      message: "Login failed"
    });
  }
}
