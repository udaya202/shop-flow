
import Product from "../models/ProductModel.js";

// CREATE PRODUCT
export async function createProduct(req, res) {
  try {
    const {
      name,
      sku,
      barcode,
      category,
      brand,
      purchasePrice,
      sellingPrice,
      stockQuantity,
      minStockLevel,
      unit,
      description
    } = req.body;

    if (
      !name?.trim() ||
      !sku?.trim() ||
      !category?.trim()
    ) {
      return res.status(400).json({
        success: false,
        message: "Name, SKU and category are required"
      });
    }

    const purchase = Number(purchasePrice);
    const selling = Number(sellingPrice);
    const stock = Number(stockQuantity ?? 0);
    const minimum = Number(minStockLevel ?? 5);

    if (
      !Number.isFinite(purchase) ||
      !Number.isFinite(selling) ||
      !Number.isFinite(stock) ||
      !Number.isFinite(minimum) ||
      purchase < 0 ||
      selling < 0 ||
      stock < 0 ||
      minimum < 0
    ) {
      return res.status(400).json({
        success: false,
        message: "Invalid price or stock values"
      });
    }

    const product = await Product.create({
      tenantId: req.user.tenantId,
      name,
      sku,
      barcode,
      category,
      brand,
      purchasePrice: purchase,
      sellingPrice: selling,
      stockQuantity: stock,
      minStockLevel: minimum,
      unit,
      description
    });

    return res.status(201).json({
      success: true,
      message: "Product created successfully",
      data: product
    });

  } catch (error) {
    if (error.code === 11000) {
      return res.status(409).json({
        success: false,
        message: "This SKU already exists in your shop"
      });
    }

    console.error("Create product error:", error);

    return res.status(500).json({
      success: false,
      message: "Unable to create product"
    });
  }
}

// GET ALL PRODUCTS
export async function getProducts(req, res) {
  try {
    const page = Math.max(1, Number(req.query.page) || 1);
    const limit = Math.min(
      100,
      Math.max(1, Number(req.query.limit) || 20)
    );

    const search = req.query.search?.trim();
    const category = req.query.category?.trim();

    const filter = {
      tenantId: req.user.tenantId,
      isActive: true
    };

    if (search) {
      const escaped = search.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      filter.$or = [
        { name: { $regex: escaped, $options: "i" } },
        { sku: { $regex: escaped, $options: "i" } },
        { barcode: { $regex: escaped, $options: "i" } },
        { brand: { $regex: escaped, $options: "i" } }
      ];
    }

    if (category) {
      filter.category = category;
    }

    const [products, total] = await Promise.all([
      Product.find(filter)
        .sort({ createdAt: -1 })
        .skip((page - 1) * limit)
        .limit(limit)
        .lean(),

      Product.countDocuments(filter)
    ]);

    return res.json({
      success: true,
      data: products,
      pagination: {
        page,
        limit,
        total,
        pages: Math.ceil(total / limit)
      }
    });

  } catch (error) {
    console.error("Get products error:", error);

    return res.status(500).json({
      success: false,
      message: "Unable to load products"
    });
  }
}

// GET SINGLE PRODUCT
export async function getProductById(req, res) {
  try {
    const product = await Product.findOne({
      _id: req.params.id,
      tenantId: req.user.tenantId,
      isActive: true
    });

    if (!product) {
      return res.status(404).json({
        success: false,
        message: "Product not found"
      });
    }

    return res.json({
      success: true,
      data: product
    });

  } catch (error) {
    return res.status(400).json({
      success: false,
      message: "Invalid product ID"
    });
  }
}

// UPDATE PRODUCT
export async function updateProduct(req, res) {
  try {
    const allowedFields = [
      "name",
      "sku",
      "barcode",
      "category",
      "brand",
      "purchasePrice",
      "sellingPrice",
      "stockQuantity",
      "minStockLevel",
      "unit",
      "description"
    ];

    const updates = {};

    for (const field of allowedFields) {
      if (req.body[field] !== undefined) {
        updates[field] = req.body[field];
      }
    }

    if (
      updates.purchasePrice !== undefined &&
      (!Number.isFinite(Number(updates.purchasePrice)) ||
        Number(updates.purchasePrice) < 0)
    ) {
      return res.status(400).json({
        success: false,
        message: "Invalid purchase price"
      });
    }

    if (
      updates.sellingPrice !== undefined &&
      (!Number.isFinite(Number(updates.sellingPrice)) ||
        Number(updates.sellingPrice) < 0)
    ) {
      return res.status(400).json({
        success: false,
        message: "Invalid selling price"
      });
    }

    for (const field of ["stockQuantity", "minStockLevel"]) {
      if (
        updates[field] !== undefined &&
        (!Number.isFinite(Number(updates[field])) ||
          Number(updates[field]) < 0)
      ) {
        return res.status(400).json({
          success: false,
          message: `Invalid ${field}`
        });
      }
    }

    for (const field of ["purchasePrice", "sellingPrice",
      "stockQuantity", "minStockLevel"]) {
      if (updates[field] !== undefined) {
        updates[field] = Number(updates[field]);
      }
    }

    const product = await Product.findOneAndUpdate(
      {
        _id: req.params.id,
        tenantId: req.user.tenantId,
        isActive: true
      },
      { $set: updates },
      { new: true, runValidators: true }
    );

    if (!product) {
      return res.status(404).json({
        success: false,
        message: "Product not found"
      });
    }

    return res.json({
      success: true,
      message: "Product updated successfully",
      data: product
    });

  } catch (error) {
    if (error.code === 11000) {
      return res.status(409).json({
        success: false,
        message: "This SKU already exists"
      });
    }

    console.error("Update product error:", error);

    return res.status(400).json({
      success: false,
      message: "Unable to update product"
    });
  }
}

// DELETE PRODUCT (SOFT DELETE)
export async function deleteProduct(req, res) {
  try {
    const product = await Product.findOneAndUpdate(
      {
        _id: req.params.id,
        tenantId: req.user.tenantId,
        isActive: true
      },
      { $set: { isActive: false } },
      { new: true }
    );

    if (!product) {
      return res.status(404).json({
        success: false,
        message: "Product not found"
      });
    }

    return res.json({
      success: true,
      message: "Product deleted successfully"
    });

  } catch (error) {
    return res.status(400).json({
      success: false,
      message: "Unable to delete product"
    });
  }
}

// LOW STOCK PRODUCTS
export async function getLowStockProducts(req, res) {
  try {
    const products = await Product.find({
      tenantId: req.user.tenantId,
      isActive: true,
      $expr: {
        $lte: ["$stockQuantity", "$minStockLevel"]
      }
    }).sort({ stockQuantity: 1 });

    return res.json({
      success: true,
      count: products.length,
      data: products
    });

  } catch (error) {
    console.error("Low stock error:", error);

    return res.status(500).json({
      success: false,
      message: "Unable to load low stock products"
    });
  }
}
