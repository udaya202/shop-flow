import Tenant from "../models/Tenant.js";

const fields = ["shopName", "email", "phone", "address", "logoUrl", "website", "businessType"];

export async function getCompanySettings(req, res) {
  try {
    const tenant = await Tenant.findOne({ _id: req.user.tenantId, status: "active" }).lean();
    if (!tenant) return res.status(404).json({ success: false, message: "Shop not found" });

    return res.json({
      success: true,
      data: {
        shopName: tenant.shopName,
        email: tenant.email,
        phone: tenant.phone || "",
        address: tenant.address || "",
        logoUrl: tenant.logoUrl || "",
        website: tenant.website || "",
        businessType: tenant.businessType || "general",
        slug: tenant.slug
      }
    });
  } catch (error) {
    console.error("Get company settings error:", error);
    return res.status(500).json({ success: false, message: "Unable to load company settings" });
  }
}

export async function updateCompanySettings(req, res) {
  try {
    const updates = {};
    for (const field of fields) {
      if (req.body[field] !== undefined) {
        if (typeof req.body[field] !== "string") {
          return res.status(400).json({ success: false, message: `Invalid ${field}` });
        }
        updates[field] = req.body[field].trim();
      }
    }
    if (updates.shopName !== undefined && !updates.shopName) {
      return res.status(400).json({ success: false, message: "Shop name is required" });
    }
    if (updates.email !== undefined) updates.email = updates.email.toLowerCase();

    const tenant = await Tenant.findOneAndUpdate(
      { _id: req.user.tenantId, status: "active" },
      { $set: updates },
      { new: true, runValidators: true }
    ).lean();

    if (!tenant) return res.status(404).json({ success: false, message: "Shop not found" });

    return res.json({
      success: true,
      message: "Company settings saved",
      data: {
        shopName: tenant.shopName,
        email: tenant.email,
        phone: tenant.phone || "",
        address: tenant.address || "",
        logoUrl: tenant.logoUrl || "",
        website: tenant.website || "",
        businessType: tenant.businessType || "general",
        slug: tenant.slug
      }
    });
  } catch (error) {
    console.error("Update company settings error:", error);
    return res.status(500).json({ success: false, message: "Unable to save company settings" });
  }
}
