import crypto from "node:crypto";
import argon2 from "argon2";

import Tenant from "../models/Tenant.js";
import User from "../models/UserModel.js";
import Session from "../models/Session.js";
import { createSessionForUser } from "./sessionController.js";

function normalizeEmail(value) {
  return String(value ?? "").trim().toLowerCase();
}

function makeBaseSlug(value) {
  return String(value ?? "")
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "")
    .slice(0, 45);
}

// PUBLIC SHOP REGISTRATION
// Creates a new tenant and its first owner, then signs the owner in immediately.
export async function registerShop(req, res) {
  let tenant = null;
  let user = null;

  try {
    const shopName = String(req.body?.shopName ?? "").trim();
    const ownerName = String(req.body?.ownerName ?? "").trim();
    const email = normalizeEmail(req.body?.email);
    const phone = String(req.body?.phone ?? "").trim();
    const password = String(req.body?.password ?? "");
    const businessType = String(req.body?.businessType ?? "general").trim();

    if (!shopName || !ownerName || !email || !password) {
      return res.status(400).json({
        success: false,
        message: "Shop name, owner name, email and password are required."
      });
    }

    if (shopName.length > 120 || ownerName.length > 120) {
      return res.status(400).json({
        success: false,
        message: "Shop name and owner name must be 120 characters or fewer."
      });
    }

    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || email.length > 254) {
      return res.status(400).json({
        success: false,
        message: "Please enter a valid email address."
      });
    }

    if (password.length < 8 || password.length > 128) {
      return res.status(400).json({
        success: false,
        message: "Password must contain between 8 and 128 characters."
      });
    }

    if (phone.length > 40) {
      return res.status(400).json({
        success: false,
        message: "Phone number is too long."
      });
    }

    let baseSlug = makeBaseSlug(shopName);
    // Sinhala, Tamil and other non-Latin shop names still receive a valid unique Shop ID.
    if (!baseSlug) baseSlug = "shop";

    // Email addresses are unique within a shop, not globally.
    // The same person may own or work in more than one tenant.
    let slug = "";
    for (let attempt = 0; attempt < 5; attempt += 1) {
      const suffix = crypto.randomBytes(3).toString("hex");
      const candidate = `${baseSlug}-${suffix}`;
      const exists = await Tenant.exists({ slug: candidate });
      if (!exists) {
        slug = candidate;
        break;
      }
    }

    if (!slug) {
      return res.status(500).json({
        success: false,
        message: "Could not generate a unique shop ID. Please try again."
      });
    }

    const passwordHash = await argon2.hash(password);

    tenant = new Tenant({
      shopName,
      slug,
      email,
      phone,
      businessType: businessType || "general",
      status: "active"
    });

    await tenant.save();

    user = new User({
      tenantId: tenant._id,
      name: ownerName,
      email,
      passwordHash,
      role: "owner",
      status: "active"
    });

    await user.save();

    // Creates a refresh-session cookie and returns a short-lived access token.
    // The browser is therefore logged in immediately after successful signup.
    const accessToken = await createSessionForUser(user, tenant, res);

    return res.status(201).json({
      success: true,
      message: "Shop created successfully. You are now signed in.",
      data: {
        accessToken,
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
        }
      }
    });
  } catch (error) {
    // Roll back partially-created registration records.
    if (user?._id && tenant?._id) {
      await Session.deleteMany({ userId: user._id, tenantId: tenant._id }).catch(() => {});
      await User.deleteOne({ _id: user._id }).catch(() => {});
    }
    if (tenant?._id) {
      await Tenant.deleteOne({ _id: tenant._id }).catch(() => {});
    }

    if (error?.code === 11000) {
      return res.status(409).json({
        success: false,
        message: "This account could not be created because a unique value already exists. Please try again."
      });
    }

    console.error("Shop registration error:", error);
    return res.status(500).json({
      success: false,
      message: "Shop registration failed. Please try again."
    });
  }
}
