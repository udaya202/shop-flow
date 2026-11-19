
import mongoose from "mongoose";
import crypto from "node:crypto";

import Product from "../models/ProductModel.js";
import Sale from "../models/SaleModel.js";
import StockMovement from "../models/StockMovementModel.js";
import Customer from "../models/CustomerModel.js";

function roundMoney(value) {
  return Math.round((value + Number.EPSILON) * 100) / 100;
}

function createInvoiceNumber() {
  const date = new Date()
    .toISOString()
    .slice(0, 10)
    .replace(/-/g, "");

  const random = crypto
    .randomBytes(4)
    .toString("hex")
    .toUpperCase();

  return `INV-${date}-${random}`;
}

// ==================================================
// CREATE POS SALE
// ==================================================

export async function createSale(req, res) {
  const session = await mongoose.startSession();

  try {
    const {
      items,
      discountAmount = 0,
      paymentMethod,
      amountPaid,
      note = "",
      customerId = null
    } = req.body;

    // Validate items
    if (!Array.isArray(items) || items.length === 0) {
      return res.status(400).json({
        success: false,
        message: "Please add products to the cart"
      });
    }

    if (items.length > 100) {
      return res.status(400).json({
        success: false,
        message: "Too many products in one sale"
      });
    }

    // Validate payment method
    const allowedMethods = ["cash", "card", "bank"];

    if (!allowedMethods.includes(paymentMethod)) {
      return res.status(400).json({
        success: false,
        message: "Invalid payment method"
      });
    }

    const discount = Number(discountAmount);

    if (!Number.isFinite(discount) || discount < 0) {
      return res.status(400).json({
        success: false,
        message: "Invalid discount amount"
      });
    }

    if (typeof note !== "string" || note.length > 500) {
      return res.status(400).json({
        success: false,
        message: "Invalid sale note"
      });
    }

    // Aggregate duplicate products.
    const quantityMap = new Map();

    for (const item of items) {
      const productId = String(item.productId ?? "");
      const quantity = Number(item.quantity);

      if (
        !mongoose.Types.ObjectId.isValid(productId) ||
        !Number.isSafeInteger(quantity) ||
        quantity <= 0
      ) {
        return res.status(400).json({
          success: false,
          message: "Invalid product or quantity"
        });
      }

      const newQuantity =
        (quantityMap.get(productId) || 0) + quantity;

      if (!Number.isSafeInteger(newQuantity)) {
        return res.status(400).json({
          success: false,
          message: "Invalid total product quantity"
        });
      }

      quantityMap.set(productId, newQuantity);
    }

    const productIds = [...quantityMap.keys()];

    const invoiceNumber = createInvoiceNumber();

    let createdSale;

    await session.withTransaction(
      async () => {
        // Fetch products belonging to this shop only.
        const products = await Product.find({
          _id: { $in: productIds },
          tenantId: req.user.tenantId,
          isActive: true
        }).session(session);

        if (products.length !== productIds.length) {
          const error = new Error(
            "One or more products were not found"
          );
          error.statusCode = 404;
          throw error;
        }

        const productMap = new Map(
          products.map(product => [
            product._id.toString(),
            product
          ])
        );

        const saleItems = [];
        const stockUpdates = [];

        let subtotal = 0;

        // Calculate prices from database.
        for (const [productId, quantity] of quantityMap) {
          const product = productMap.get(productId);

          if (product.stockQuantity < quantity) {
            const error = new Error(
              `Insufficient stock for ${product.name}. Available: ${product.stockQuantity}`
            );
            error.statusCode = 409;
            throw error;
          }

          const unitPrice = roundMoney(
            product.sellingPrice
          );

          const purchasePrice = roundMoney(
            product.purchasePrice
          );

          const lineTotal = roundMoney(
            unitPrice * quantity
          );

          subtotal = roundMoney(subtotal + lineTotal);

          saleItems.push({
            productId: product._id,
            name: product.name,
            sku: product.sku,
            quantity,
            unit: product.unit,
            unitPrice,
            purchasePrice,
            lineTotal
          });

          stockUpdates.push({
            product,
            quantity
          });
        }

        if (discount > subtotal) {
          const error = new Error(
            "Discount cannot exceed subtotal"
          );
          error.statusCode = 400;
          throw error;
        }

        const totalAmount = roundMoney(
          subtotal - discount
        );

        const paidAmount =
          amountPaid === undefined || amountPaid === null
            ? totalAmount
            : Number(amountPaid);

        if (
          !Number.isFinite(paidAmount) ||
          paidAmount < totalAmount
        ) {
          const error = new Error(
            "Insufficient payment amount"
          );
          error.statusCode = 400;
          throw error;
        }

        if (
          paymentMethod !== "cash" &&
          roundMoney(paidAmount) !== totalAmount
        ) {
          const error = new Error(
            "Card and bank payments must equal the invoice total"
          );
          error.statusCode = 400;
          throw error;
        }

        const changeAmount = paymentMethod === "cash"
          ? roundMoney(paidAmount - totalAmount)
          : 0;

        // Resolve the selected customer within this tenant only.
        let customerSnapshot = {
          name: "",
          phone: "",
          email: "",
          address: ""
        };

        if (customerId) {
          if (!mongoose.Types.ObjectId.isValid(String(customerId))) {
            const error = new Error("Invalid customer");
            error.statusCode = 400;
            throw error;
          }

          const customer = await Customer.findOne({
            _id: customerId,
            tenantId: req.user.tenantId,
            isActive: true
          }).session(session);

          if (!customer) {
            const error = new Error("Customer not found in this shop");
            error.statusCode = 404;
            throw error;
          }

          customerSnapshot = {
            name: customer.name,
            phone: customer.phone || "",
            email: customer.email || "",
            address: customer.address || ""
          };
        }

        // Create sale document.
        const sale = new Sale({
          tenantId: req.user.tenantId,
          invoiceNumber,
          customerId: customerId || null,
          customerSnapshot,
          items: saleItems,
          subtotal,
          discountAmount: discount,
          totalAmount,
          paymentMethod,
          amountPaid: paidAmount,
          changeAmount,
          paymentStatus: "paid",
          note: note.trim(),
          createdBy: req.user.id
        });

        await sale.save({ session });

        // Update stock and create movement records.
        const movements = [];

        for (const entry of stockUpdates) {
          const { product, quantity } = entry;

          const stockBefore = product.stockQuantity;
          const stockAfter = stockBefore - quantity;

          const updateResult = await Product.updateOne(
            {
              _id: product._id,
              tenantId: req.user.tenantId,
              isActive: true,
              stockQuantity: { $gte: quantity }
            },
            {
              $inc: {
                stockQuantity: -quantity
              }
            },
            { session }
          );

          if (updateResult.matchedCount !== 1) {
            const error = new Error(
              `Stock changed while processing ${product.name}. Please retry.`
            );
            error.statusCode = 409;
            throw error;
          }

          movements.push({
            tenantId: req.user.tenantId,
            productId: product._id,
            movementType: "sale",
            quantityChange: -quantity,
            stockBefore,
            stockAfter,
            referenceId: sale._id,
            note: `Sale ${invoiceNumber}`,
            createdBy: req.user.id
          });
        }

        if (movements.length > 0) {
          await StockMovement.insertMany(
            movements,
            { session }
          );
        }

        createdSale = sale;
      },
      {
        readPreference: "primary",
        readConcern: { level: "snapshot" },
        writeConcern: { w: "majority" }
      }
    );

    return res.status(201).json({
      success: true,
      message: "Sale completed successfully",
      data: createdSale
    });

  } catch (error) {
    console.error("Create sale error:", error);

    if (error.code === 11000) {
      return res.status(409).json({
        success: false,
        message: "Invoice number conflict. Please retry."
      });
    }

    return res.status(error.statusCode || 500).json({
      success: false,
      message: error.statusCode
        ? error.message
        : "Unable to complete sale"
    });

  } finally {
    await session.endSession();
  }
}

// ==================================================
// GET SALES HISTORY
// ==================================================

export async function getSales(req, res) {
  try {
    const page = Math.max(
      1,
      Number(req.query.page) || 1
    );

    const limit = Math.min(
      100,
      Math.max(1, Number(req.query.limit) || 20)
    );

    const filter = {
      tenantId: req.user.tenantId
    };

    const search = req.query.search?.trim();

    if (search) {
      const escaped = search.replace(
        /[.*+?^${}()|[\]\\]/g,
        "\\$&"
      );

      filter.invoiceNumber = {
        $regex: escaped,
        $options: "i"
      };
    }

    const [sales, total] = await Promise.all([
      Sale.find(filter)
        .sort({ createdAt: -1 })
        .skip((page - 1) * limit)
        .limit(limit)
        .lean(),

      Sale.countDocuments(filter)
    ]);

    return res.json({
      success: true,
      data: sales,
      pagination: {
        page,
        limit,
        total,
        pages: Math.ceil(total / limit)
      }
    });

  } catch (error) {
    console.error("Get sales error:", error);

    return res.status(500).json({
      success: false,
      message: "Unable to load sales"
    });
  }
}

// ==================================================
// GET SINGLE SALE
// ==================================================

export async function getSaleById(req, res) {
  try {
    if (!mongoose.Types.ObjectId.isValid(req.params.id)) {
      return res.status(400).json({
        success: false,
        message: "Invalid sale ID"
      });
    }

    const sale = await Sale.findOne({
      _id: req.params.id,
      tenantId: req.user.tenantId
    }).lean();

    if (!sale) {
      return res.status(404).json({
        success: false,
        message: "Sale not found"
      });
    }

    return res.json({
      success: true,
      data: sale
    });

  } catch (error) {
    console.error("Get sale error:", error);

    return res.status(500).json({
      success: false,
      message: "Unable to load sale"
    });
  }
}
