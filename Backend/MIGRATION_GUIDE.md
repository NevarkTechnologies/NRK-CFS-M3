# Data Migration Guide: String to ObjectId References

This guide helps you migrate existing data from string-based vendor IDs to proper MongoDB ObjectId references.

## Migration Overview

**Before:** Cafes and MenuItems used string `vendorId` fields (e.g., "ADMIN_01")  
**After:** Use proper ObjectId references to User documents

## Step 1: Update Existing Data (One-time)

Run this in MongoDB or via Node script:

### Option A: Using MongoDB Shell

```javascript
// In MongoDB shell (mongosh)

// 1. Get all vendors
const vendors = db.users.find({ role: 'vendor' });

// 2. For each vendor, update their cafes
vendors.forEach(vendor => {
  // Update cafes owned by this vendor (string ID match)
  db.cafes.updateMany(
    { legacyVendorId: vendor.vendorId || 'ADMIN_01' },
    { $set: { vendorId: vendor._id } }
  );
  
  // Update menu items for this vendor (string ID match)
  db.menuitems.updateMany(
    { legacyVendorId: vendor.vendorId || 'ADMIN_01' },
    { $set: { vendorId: vendor._id } }
  );
});

// 3. Verify migration
db.cafes.find({ vendorId: { $exists: true, $ne: null } }).count();
db.menuitems.find({ vendorId: { $exists: true, $ne: null } }).count();
```

### Option B: Using Node.js Script

Create a file `migrate.js` in your Backend directory:

```javascript
const mongoose = require('mongoose');
const User = require('./models/user');
const Cafe = require('./models/cafe');
const MenuItem = require('./models/menuitems');
require('dotenv').config();

async function migrate() {
  try {
    await mongoose.connect(process.env.MONGO_URI || 'mongodb://localhost:27017/nevark');
    console.log('Connected to MongoDB');

    // Get all vendors
    const vendors = await User.find({ role: 'vendor' });
    console.log(`Found ${vendors.length} vendors`);

    let cafeUpdates = 0;
    let itemUpdates = 0;

    // For each vendor, update their cafes and menu items
    for (const vendor of vendors) {
      const vendorIdentifier = vendor.vendorId || 'ADMIN_01';

      // Update cafes
      const cafeResult = await Cafe.updateMany(
        { legacyVendorId: vendorIdentifier, vendorId: { $exists: false } },
        { $set: { vendorId: vendor._id } }
      );
      cafeUpdates += cafeResult.modifiedCount;

      // Update menu items
      const itemResult = await MenuItem.updateMany(
        { legacyVendorId: vendorIdentifier, vendorId: { $exists: false } },
        { $set: { vendorId: vendor._id } }
      );
      itemUpdates += itemResult.modifiedCount;

      // Update user's cafeId if they have a cafe
      const cafe = await Cafe.findOne({ vendorId: vendor._id });
      if (cafe && !vendor.cafeId) {
        await User.findByIdAndUpdate(vendor._id, { cafeId: cafe._id });
      }
    }

    console.log(`✓ Updated ${cafeUpdates} cafes`);
    console.log(`✓ Updated ${itemUpdates} menu items`);

    // Verify
    const cafeCount = await Cafe.countDocuments({ vendorId: { $exists: true, $ne: null } });
    const itemCount = await MenuItem.countDocuments({ vendorId: { $exists: true, $ne: null } });
    
    console.log(`\nVerification:`);
    console.log(`- Cafes with vendorId: ${cafeCount}`);
    console.log(`- MenuItems with vendorId: ${itemCount}`);
    console.log(`\n✓ Migration completed successfully!`);

    await mongoose.connection.close();
  } catch (error) {
    console.error('Migration error:', error);
    process.exit(1);
  }
}

migrate();
```

**Run the migration:**
```bash
cd Backend
node migrate.js
```

## Step 2: Verify Migration

```bash
# In your Node.js app or postman:

# 1. Verify cafes have vendor references
GET /api/cafes

# Response should show populated vendorId:
{
  "_id": "CAFE_ID",
  "name": "Coffee House",
  "vendorId": {
    "_id": "USER_ID",
    "name": "John Vendor",
    "email": "vendor@example.com"
  }
}

# 2. Verify vendors have cafe references
GET /api/vendors/USER_ID/cafes

# 3. Verify menu items have vendor references
GET /api/vendors/USER_ID/menu
```

## Step 3: Update Your Frontend

### Previously (string-based):
```javascript
// Getting menu items by vendor
fetch(`/api/menu?vendorId=ADMIN_01`)
```

### Now (ObjectId-based):
```javascript
// Getting menu items by vendor (using user ID)
fetch(`/api/menu?vendorId=${userId}`)

// Or use the dedicated endpoint
fetch(`/api/vendors/${userId}/menu`)
```

### Example Flutter Code Update:

**Before:**
```dart
final response = await http.get(
  Uri.parse('${ApiConfig.baseUrl}/menu?vendorId=ADMIN_01'),
);
```

**After:**
```dart
final response = await http.get(
  Uri.parse('${ApiConfig.baseUrl}/vendors/$vendorId/menu'),
);
// Or use the user's ID from Firebase authentication
```

## Step 4: Environment & Setup

Ensure your `.env` file has:
```
MONGO_URI=mongodb://your-connection-string
```

## Verification Checklist

- [ ] Migration script runs without errors
- [ ] Cafe documents have `vendorId` as ObjectId
- [ ] MenuItem documents have `vendorId` as ObjectId
- [ ] User documents have `cafeId` as ObjectId
- [ ] API endpoints return populated vendor/cafe information
- [ ] Vendors can log in via Firebase and get their cafe auto-linked
- [ ] Menu items can be queried by vendor ID
- [ ] Cafes can be queried with vendor information

## Rollback (if needed)

If you need to revert:
```javascript
// Restore legacyVendorId values
db.cafes.updateMany(
  { vendorId: { $exists: true } },
  [{ $set: { vendorId: '$legacyVendorId' } }]
);

db.menuitems.updateMany(
  { vendorId: { $exists: true } },
  [{ $set: { vendorId: '$legacyVendorId' } }]
);
```

## Troubleshooting

**Issue:** "vendorId is not a valid ObjectId"
- **Solution:** Ensure you're passing actual MongoDB user `_id` values, not custom vendorId strings

**Issue:** Cafes not appearing with vendor info
- **Solution:** Run `/api/cafes?populate=vendorId` or check that populate is working in your queries

**Issue:** Menu items not linked to vendor
- **Solution:** Verify the migration script ran successfully using verification queries above

## Timeline

- **Before Migration:** System works with string IDs
- **After Migration:** System works with both (backwards compatible)
- **Legacy Fields:** `legacyVendorId` retained for reference but not used in queries

---

For questions or issues, refer to [VENDOR_CAFE_RELATIONSHIP.md](./VENDOR_CAFE_RELATIONSHIP.md)
