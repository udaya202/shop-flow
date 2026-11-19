import mongoose from "mongoose";
import Customer from "../models/CustomerModel.js";
import Sale from "../models/SaleModel.js";

function clean(value) {
  return typeof value === "string" ? value.trim() : "";
}

export async function getCustomers(req, res) {
  try {
    const filter = { tenantId: req.user.tenantId, isActive: true };
    const search = clean(req.query.search);
    if (search) {
      const escaped = search.replace(
        /[.*+?^${}()|[\]\\]/g,
        "\\$&"
      );
      filter.$or = [
        { name: { $regex: escaped, $options: "i" } },
        { phone: { $regex: escaped, $options: "i" } },
        { email: { $regex: escaped, $options: "i" } }
      ];
    }
    const customers = await Customer.find(filter).sort({ name: 1 }).limit(200).lean();
    return res.json({ success: true, data: customers });
  } catch (error) {
    console.error("Get customers error:", error);
    return res.status(500).json({ success: false, message: "Unable to load customers" });
  }
}

export async function createCustomer(req, res) {
  try {
    const name = clean(req.body.name);
    if (!name) {
      return res.status(400).json({ success: false, message: "Customer name is required" });
    }
    const customer = await Customer.create({
      tenantId: req.user.tenantId,
      name,
      phone: clean(req.body.phone),
      email: clean(req.body.email).toLowerCase(),
      address: clean(req.body.address),
      notes: clean(req.body.notes)
    });
    return res.status(201).json({ success: true, message: "Customer created", data: customer });
  } catch (error) {
    console.error("Create customer error:", error);
    return res.status(500).json({ success: false, message: "Unable to create customer" });
  }
}

export async function updateCustomer(req, res) {
  try {
    if (!mongoose.Types.ObjectId.isValid(req.params.id)) {
      return res.status(400).json({ success: false, message: "Invalid customer ID" });
    }
    const updates = {};
    for (const field of ["name", "phone", "email", "address", "notes"]) {
      if (req.body[field] !== undefined) updates[field] = clean(req.body[field]);
    }
    if (updates.name !== undefined && !updates.name) {
      return res.status(400).json({ success: false, message: "Customer name is required" });
    }
    if (updates.email !== undefined) updates.email = updates.email.toLowerCase();

    const customer = await Customer.findOneAndUpdate(
      { _id: req.params.id, tenantId: req.user.tenantId, isActive: true },
      { $set: updates },
      { new: true, runValidators: true }
    );
    if (!customer) {
      return res.status(404).json({ success: false, message: "Customer not found" });
    }
    return res.json({ success: true, message: "Customer updated", data: customer });
  } catch (error) {
    console.error("Update customer error:", error);
    return res.status(400).json({ success: false, message: "Unable to update customer" });
  }
}

export async function deleteCustomer(req, res) {
  try {
    if (!mongoose.Types.ObjectId.isValid(req.params.id)) {
      return res.status(400).json({ success: false, message: "Invalid customer ID" });
    }
    const customer = await Customer.findOneAndUpdate(
      { _id: req.params.id, tenantId: req.user.tenantId, isActive: true },
      { $set: { isActive: false } },
      { new: true }
    );
    if (!customer) {
      return res.status(404).json({ success: false, message: "Customer not found" });
    }
    return res.json({ success: true, message: "Customer deleted" });
  } catch (error) {
    console.error("Delete customer error:", error);
    return res.status(500).json({ success: false, message: "Unable to delete customer" });
  }
}

export async function getCustomerSales(req, res) {
  try {
    if (!mongoose.Types.ObjectId.isValid(req.params.id)) {
      return res.status(400).json({ success: false, message: "Invalid customer ID" });
    }
    const customer = await Customer.findOne({
      _id: req.params.id, tenantId: req.user.tenantId
    }).lean();
    if (!customer) {
      return res.status(404).json({ success: false, message: "Customer not found" });
    }
    const sales = await Sale.find({
      tenantId: req.user.tenantId, customerId: customer._id
    }).sort({ createdAt: -1 }).limit(100).lean();
    return res.json({ success: true, customer, data: sales });
  } catch (error) {
    console.error("Customer sales error:", error);
    return res.status(500).json({ success: false, message: "Unable to load customer history" });
  }
}
