
import crypto from "node:crypto";
import jwt from "jsonwebtoken";
import argon2 from "argon2";

import User from "../models/UserModel.js";
import Tenant from "../models/Tenant.js";
import Session from "../models/Session.js";

const COOKIE_NAME = "shopflow_refresh";

const SESSION_DAYS = 30;

const cookieOptions = {
  httpOnly: true,
  secure: process.env.NODE_ENV === "production",
  sameSite: "lax",
  path: "/api/auth",
  maxAge: SESSION_DAYS * 24 * 60 * 60 * 1000
};

function hashToken(token) {
  return crypto
    .createHash("sha256")
    .update(token)
    .digest("hex");
}

function createAccessToken(user, tenant) {
  return jwt.sign(
    {
      userId: user._id.toString(),
      tenantId: tenant._id.toString(),
      role: user.role
    },
    process.env.JWT_ACCESS_SECRET,
    { expiresIn: "15m" }
  );
}

export async function createSessionForUser(user, tenant, res) {
  const refreshToken = crypto.randomBytes(48).toString("hex");

  const expiresAt = new Date(
    Date.now() + SESSION_DAYS * 24 * 60 * 60 * 1000
  );

  await Session.create({
    userId: user._id,
    tenantId: tenant._id,
    tokenHash: hashToken(refreshToken),
    expiresAt
  });

  res.cookie(COOKIE_NAME, refreshToken, cookieOptions);

  return createAccessToken(user, tenant);
}

// SESSION LOGIN
export async function sessionLogin(req, res) {
  try {
    const { shopSlug, email, password } = req.body;

    if (!shopSlug || !email || !password) {
      return res.status(400).json({
        success: false,
        message: "Shop ID, email and password are required"
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

    const valid = await argon2.verify(
      user.passwordHash,
      password
    );

    if (!valid) {
      return res.status(401).json({
        success: false,
        message: "Invalid login details"
      });
    }

    const accessToken = await createSessionForUser(
      user,
      tenant,
      res
    );

    return res.status(200).json({
      success: true,
      message: "Login successful",
      data: {
        accessToken,
        user: {
          id: user._id,
          name: user.name,
          email: user.email,
          role: user.role
        },
        shop: {
          id: tenant._id,
          shopName: tenant.shopName,
          slug: tenant.slug
        }
      }
    });

  } catch (error) {
    console.error("Session login error:", error);

    return res.status(500).json({
      success: false,
      message: "Login failed"
    });
  }
}

// REFRESH ACCESS TOKEN
export async function refreshSession(req, res) {
  try {
    const oldToken = req.cookies?.[COOKIE_NAME];

    if (!oldToken) {
      return res.status(401).json({
        success: false,
        message: "No active session"
      });
    }

    const oldHash = hashToken(oldToken);

    const session = await Session.findOne({
      tokenHash: oldHash,
      expiresAt: { $gt: new Date() }
    });

    if (!session) {
      res.clearCookie(COOKIE_NAME, cookieOptions);

      return res.status(401).json({
        success: false,
        message: "Session expired. Please login again."
      });
    }

    const user = await User.findOne({
      _id: session.userId,
      tenantId: session.tenantId,
      status: "active"
    });

    const tenant = await Tenant.findOne({
      _id: session.tenantId,
      status: "active"
    });

    if (!user || !tenant) {
      await Session.deleteOne({ _id: session._id });
      res.clearCookie(COOKIE_NAME, cookieOptions);

      return res.status(401).json({
        success: false,
        message: "Account unavailable"
      });
    }

    // Rotate the refresh token.
    await Session.deleteOne({ _id: session._id });

    const accessToken = await createSessionForUser(
      user,
      tenant,
      res
    );

    return res.json({
      success: true,
      message: "Session refreshed",
      data: {
        accessToken,
        user: {
          id: user._id,
          name: user.name,
          email: user.email,
          role: user.role
        },
        shop: {
          id: tenant._id,
          shopName: tenant.shopName,
          slug: tenant.slug
        }
      }
    });

  } catch (error) {
    console.error("Refresh error:", error);

    return res.status(500).json({
      success: false,
      message: "Unable to refresh session"
    });
  }
}

// LOGOUT
export async function sessionLogout(req, res) {
  try {
    const token = req.cookies?.[COOKIE_NAME];

    if (token) {
      await Session.deleteOne({
        tokenHash: hashToken(token)
      });
    }

    res.clearCookie(COOKIE_NAME, cookieOptions);

    return res.json({
      success: true,
      message: "Logged out successfully"
    });

  } catch (error) {
    console.error("Logout error:", error);

    return res.status(500).json({
      success: false,
      message: "Logout failed"
    });
  }
}
