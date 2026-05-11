const mongoose = require('mongoose');
const path = require('path');
require('dotenv').config({ path: path.resolve(__dirname, '.env') });

const User = require('./models/user');
const Cafe = require('./models/cafe');
const MenuItem = require('./models/menuitems');

async function migrate() {
  const mongoUri = process.env.MONGO_URI;
  if (!mongoUri) {
    console.error('MONGO_URI is not defined in Backend/.env');
    process.exit(1);
  }

  await mongoose.connect(mongoUri);

  try {
    console.log('Connected to MongoDB Atlas');

    const vendors = await User.find({ role: 'vendor' });
    console.log(`Found ${vendors.length} vendor users`);

    let cafeUpdates = 0;
    let menuItemUpdates = 0;
    let userCafeUpdates = 0;

    for (const vendor of vendors) {
      const vendorObjectId = vendor._id;
      const vendorGoogleId = vendor.googleId?.toString() ?? '';

      const cafeFilter = {
        $or: [
          { vendorId: vendorObjectId },
          ...(vendorObjectId ? [{ vendorId: vendorObjectId.toString() }] : []),
          ...(vendorGoogleId ? [{ vendorId: vendorGoogleId }] : []),
          { legacyVendorId: vendorGoogleId },
        ],
      };

      const cafeResult = await Cafe.collection.updateMany(cafeFilter, {
        $set: { vendorId: vendorObjectId },
        $setOnInsert: { legacyVendorId: vendorGoogleId },
      });

      cafeUpdates += cafeResult.modifiedCount || 0;

      const menuItemFilter = {
        $or: [
          { vendorId: vendorObjectId },
          ...(vendorObjectId ? [{ vendorId: vendorObjectId.toString() }] : []),
          ...(vendorGoogleId ? [{ vendorId: vendorGoogleId }] : []),
          { legacyVendorId: vendorGoogleId },
        ],
      };

      const menuItemResult = await MenuItem.collection.updateMany(menuItemFilter, {
        $set: { vendorId: vendorObjectId },
        $setOnInsert: { legacyVendorId: vendorGoogleId },
      });

      menuItemUpdates += menuItemResult.modifiedCount || 0;

      const cafeMatchFilter = {
        $or: [
          { vendorId: vendorObjectId },
          { legacyVendorId: vendorGoogleId },
        ],
      };
      const cafe = await Cafe.findOne(cafeMatchFilter);
      if (cafe && (!vendor.cafeId || vendor.cafeId.toString() !== cafe._id.toString())) {
        await User.updateOne({ _id: vendorObjectId }, { $set: { cafeId: cafe._id } });
        userCafeUpdates += 1;
        console.log(`Linked vendor ${vendorObjectId} to cafe ${cafe._id}`);
      }
    }

    // Convert any remaining string-based vendorId values into legacyVendorId and clear vendorId
    const orphanCafeResult = await Cafe.collection.updateMany(
      { vendorId: { $type: 'string' } },
      [
        {
          $set: {
            legacyVendorId: {
              $cond: {
                if: { $or: [{ $eq: ['$legacyVendorId', null] }, { $eq: ['$legacyVendorId', ''] }] },
                then: '$vendorId',
                else: '$legacyVendorId',
              },
            },
            vendorId: null,
          },
        },
      ]
    );
    const orphanMenuResult = await MenuItem.collection.updateMany(
      { vendorId: { $type: 'string' } },
      [
        {
          $set: {
            legacyVendorId: {
              $cond: {
                if: { $or: [{ $eq: ['$legacyVendorId', null] }, { $eq: ['$legacyVendorId', ''] }] },
                then: '$vendorId',
                else: '$legacyVendorId',
              },
            },
            vendorId: null,
          },
        },
      ]
    );

    if (orphanCafeResult.modifiedCount) {
      console.log(`Converted ${orphanCafeResult.modifiedCount} orphan cafe vendorIds into legacyVendorId`);
    }
    if (orphanMenuResult.modifiedCount) {
      console.log(`Converted ${orphanMenuResult.modifiedCount} orphan menu vendorIds into legacyVendorId`);
    }

    const cafesWithObjectIdVendors = await Cafe.countDocuments({ vendorId: { $type: 'objectId' } });
    const menuItemsWithObjectIdVendors = await MenuItem.countDocuments({ vendorId: { $type: 'objectId' } });
    const usersWithCafeId = await User.countDocuments({ cafeId: { $type: 'objectId' } });

    console.log('\nMigration completed');
    console.log(`- Cafe documents updated: ${cafeUpdates}`);
    console.log(`- MenuItem documents updated: ${menuItemUpdates}`);
    console.log(`- Vendor users linked to cafes: ${userCafeUpdates}`);
    console.log(`- Cafes with objectId vendorId: ${cafesWithObjectIdVendors}`);
    console.log(`- MenuItems with objectId vendorId: ${menuItemsWithObjectIdVendors}`);
    console.log(`- Users with objectId cafeId: ${usersWithCafeId}`);
  } catch (error) {
    console.error('Migration error:', error);
  } finally {
    await mongoose.disconnect();
    console.log('MongoDB connection closed');
  }
}

migrate();