import dotenv from "dotenv";
import mongoose from "mongoose";
import argon2 from "argon2";
import { connectDatabase } from "../config/database.js";
import SuperAdmin from "../models/SuperAdmin.js";

dotenv.config();

async function main() {
  const name = String(process.env.SUPER_ADMIN_NAME ?? "").trim();
  const email = String(process.env.SUPER_ADMIN_EMAIL ?? "").trim().toLowerCase();
  const password = String(process.env.SUPER_ADMIN_PASSWORD ?? "");

  if (!name || !email || password.length < 12) {
    throw new Error("Set SUPER_ADMIN_NAME, SUPER_ADMIN_EMAIL and a SUPER_ADMIN_PASSWORD of at least 12 characters in backend/.env");
  }

  await connectDatabase();

  const existing = await SuperAdmin.findOne({});
  if (existing) {
    throw new Error("A Super Admin already exists. Bootstrap is one-time and will not create or promote another account.");
  }

  const passwordHash = await argon2.hash(password);
  await SuperAdmin.create({ name, email, passwordHash, status: "active" });
  console.log(`Super Admin created: ${email}`);
}

main()
  .catch(error => {
    console.error("Super Admin bootstrap failed:", error.message);
    process.exitCode = 1;
  })
  .finally(async () => {
    await mongoose.disconnect().catch(() => {});
  });
