
import mongoose from "mongoose";

const stockMovementSchema = new mongoose.Schema(
  {
    tenantId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "Tenant",
      required: true,
      index: true
    },

    productId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "Product",
      required: true
    },

    movementType: {
      type: String,
      enum: ["sale", "purchase", "adjustment", "return"],
      required: true
    },

    quantityChange: {
      type: Number,
      required: true
    },

    stockBefore: {
      type: Number,
      required: true
    },

    stockAfter: {
      type: Number,
      required: true
    },

    referenceId: {
      type: mongoose.Schema.Types.ObjectId,
      required: true
    },

    note: {
      type: String,
      default: ""
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

stockMovementSchema.index(
  { tenantId: 1, productId: 1, createdAt: -1 }
);

const StockMovement = mongoose.model(
  "StockMovement",
  stockMovementSchema
);

export default StockMovement;
