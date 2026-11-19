
import mongoose from "mongoose";

const productSchema = new mongoose.Schema(
  {
    tenantId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "Tenant",
      required: true,
      index: true
    },

    name: {
      type: String,
      required: true,
      trim: true,
      maxlength: 150
    },

    sku: {
      type: String,
      required: true,
      trim: true,
      uppercase: true
    },

    barcode: {
      type: String,
      trim: true,
      default: ""
    },

    category: {
      type: String,
      required: true,
      trim: true
    },

    brand: {
      type: String,
      trim: true,
      default: ""
    },

    purchasePrice: {
      type: Number,
      required: true,
      min: 0
    },

    sellingPrice: {
      type: Number,
      required: true,
      min: 0
    },

    stockQuantity: {
      type: Number,
      default: 0,
      min: 0
    },

    minStockLevel: {
      type: Number,
      default: 5,
      min: 0
    },

    unit: {
      type: String,
      default: "pcs",
      trim: true
    },

    description: {
      type: String,
      default: "",
      trim: true
    },

    isActive: {
      type: Boolean,
      default: true
    }
  },
  {
    timestamps: true
  }
);

// SKU must be unique within each shop.
productSchema.index(
  { tenantId: 1, sku: 1 },
  { unique: true }
);

productSchema.index(
  { tenantId: 1, name: 1 }
);

productSchema.index(
  { tenantId: 1, category: 1 }
);

const Product = mongoose.model("Product", productSchema);

export default Product;
