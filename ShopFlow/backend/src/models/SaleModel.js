
import mongoose from "mongoose";

const saleItemSchema = new mongoose.Schema(
  {
    productId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "Product",
      required: true
    },

    name: {
      type: String,
      required: true
    },

    sku: {
      type: String,
      required: true
    },

    quantity: {
      type: Number,
      required: true,
      min: 1
    },

    unit: {
      type: String,
      default: "pcs"
    },

    unitPrice: {
      type: Number,
      required: true,
      min: 0
    },

    purchasePrice: {
      type: Number,
      required: true,
      min: 0
    },

    lineTotal: {
      type: Number,
      required: true,
      min: 0
    }
  },
  { _id: false }
);

const saleSchema = new mongoose.Schema(
  {
    tenantId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "Tenant",
      required: true,
      index: true
    },

    invoiceNumber: {
      type: String,
      required: true
    },

    // Optional for compatibility with historical invoices created before customer management.
    customerId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "Customer",
      default: null,
      index: true
    },

    customerSnapshot: {
      name: { type: String, default: "" },
      phone: { type: String, default: "" },
      email: { type: String, default: "" },
      address: { type: String, default: "" }
    },

    items: {
      type: [saleItemSchema],
      required: true,
      validate: {
        validator: items => items.length > 0,
        message: "Sale must contain at least one item"
      }
    },

    subtotal: {
      type: Number,
      required: true,
      min: 0
    },

    discountAmount: {
      type: Number,
      default: 0,
      min: 0
    },

    totalAmount: {
      type: Number,
      required: true,
      min: 0
    },

    paymentMethod: {
      type: String,
      enum: ["cash", "card", "bank"],
      required: true
    },

    amountPaid: {
      type: Number,
      required: true,
      min: 0
    },

    changeAmount: {
      type: Number,
      default: 0,
      min: 0
    },

    paymentStatus: {
      type: String,
      enum: ["paid"],
      default: "paid"
    },

    note: {
      type: String,
      default: "",
      maxlength: 500
    },

    createdBy: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      required: true
    }
  },
  {
    timestamps: true
  }
);

saleSchema.index(
  { tenantId: 1, invoiceNumber: 1 },
  { unique: true }
);

saleSchema.index(
  { tenantId: 1, createdAt: -1 }
);

const Sale = mongoose.model("Sale", saleSchema);

export default Sale;
