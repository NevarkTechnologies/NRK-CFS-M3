const mongoose = require('mongoose');
require('dotenv').config();

const Cafe = require('./models/cafe');
const MenuItem = require('./models/menuitems');
const User = require('./models/user');

const vendorId = 'ADMIN_01';

const cafes = [
  {
    name: 'Madno - House of Sundaes and Waffles',
    slug: 'madno-sundaes-waffles',
    rating: 4.4,
    reviews: 413,
    time: '45-50 mins',
    image: 'assets/cafes/cafe3.jpg',
    category: 'Desserts',
    cuisine: 'Ice Cream, Desserts',
    price: 'Rs 500 for two',
    tag: 'Pure Veg',
    offer: 'Buy 1 get 1',
    location: 'Madno, 3.9 km',
    vendorId,
  },
  {
    name: 'Dindigul Thalappakatti',
    slug: 'dindigul-thalappakatti',
    rating: 4.3,
    reviews: 520,
    time: '45-55 mins',
    image: 'assets/cafes/cafe1.jpg',
    category: 'South Indian',
    cuisine: 'Biryani, South Indian',
    price: 'Rs 400 for two',
    tag: 'Hyderabadi',
    offer: '20% off',
    location: 'Thalappakatti, 2.7 km',
    vendorId: 'VENDOR_02',
  },
  {
    name: 'Baskin Robbins - Ice Cream Delight',
    slug: 'baskin-robbins-ice-cream',
    rating: 4.5,
    reviews: 784,
    time: '25-30 mins',
    image: 'assets/cafes/cafe2.jpg',
    category: 'Desserts',
    cuisine: 'Ice Cream, Desserts',
    price: 'Rs 350 for two',
    tag: 'Premium',
    offer: 'Buy 1 get 1',
    location: 'Baskin, 1.2 km',
    vendorId: 'VENDOR_03',
  },
  {
    name: 'Cafe Lounge Express',
    slug: 'cafe-lounge-express',
    rating: 4.2,
    reviews: 298,
    time: '30-40 mins',
    image: 'assets/cafes/cafe1.jpg',
    category: 'Cafe',
    cuisine: 'Coffee, Snacks',
    price: 'Rs 320 for two',
    tag: 'Quick Bite',
    offer: '10% off',
    location: 'Central, 1.8 km',
    vendorId: 'VENDOR_04',
  },
];

function menuForCafe(cafe) {
  const image = cafe.image;
  if (cafe.slug.includes('baskin') || cafe.slug.includes('madno')) {
    return [
      ['Chocolate Fudge Sundae', 220, 'Sundaes', 'Rich chocolate ice cream with hot fudge, nuts, and cherry.', true],
      ['Mint Choc Chip Scoop', 120, 'Scoops', 'Refreshing mint ice cream with chocolate chips.', true],
      ['Strawberry Milkshake', 160, 'Shakes', 'Thick and creamy strawberry shake.', true],
      ['Belgian Waffle', 190, 'Waffles', 'Warm waffle topped with vanilla ice cream and syrup.', true],
    ];
  }

  if (cafe.slug.includes('lounge')) {
    return [
      ['Caramel Macchiato', 220, 'Hot Coffees', 'Freshly steamed milk with vanilla-flavored syrup.', true],
      ['Iced Vanilla Latte', 240, 'Cold Coffees', 'Espresso poured over ice and milk.', true],
      ['Blueberry Muffin', 150, 'Bakery', 'Soft muffin baked with fresh blueberries.', true],
      ['Butter Croissant', 130, 'Bakery', 'Flaky, buttery, authentic French croissant.', true],
    ];
  }

  return [
    ['Chicken Biryani', 220, 'Mains', 'Spicy traditional biryani with tender chicken pieces.', false],
    ['Paneer Butter Masala', 190, 'Mains', 'Cottage cheese cubes in a rich tomato gravy.', true],
    ['Paneer Tikka', 180, 'Starters', 'Grilled paneer cubes marinated in spices.', true],
    ['Masala French Fries', 110, 'Snacks', 'Crispy fries with Indian spices.', true],
    ['Fresh Lime Soda', 70, 'Beverages', 'Refreshing sweet and salt lime soda.', true],
  ];
}

async function seed() {
  if (!process.env.MONGO_URI) {
    throw new Error('MONGO_URI is missing. Add it to Backend/.env');
  }

  await mongoose.connect(process.env.MONGO_URI);
  await MenuItem.deleteMany({});
  await Cafe.deleteMany({});
  await User.deleteMany({});

  const createdCafes = await Cafe.insertMany(cafes);
  const primaryCafe = createdCafes[0];
  await User.insertMany([
    {
      googleId: 'google_customer_001',
      name: 'Demo Customer',
      email: 'customer@nevark.test',
      role: 'customer',
      address: {
        street1: 'Nevark Campus',
        street2: 'Food Court Entrance',
        district: 'Hosur',
        state: 'Tamil Nadu',
        country: 'India',
        pincode: '635109',
      },
      paymentLabel: 'UPI',
    },
    {
      googleId: 'google_vendor_001',
      name: 'Madno Vendor',
      email: 'vendor@nevark.test',
      role: 'vendor',
      vendorId,
      cafeId: primaryCafe._id,
      address: {
        street1: 'Madno Counter',
        street2: 'Nevark Cafeteria',
        district: 'Hosur',
        state: 'Tamil Nadu',
        country: 'India',
        pincode: '635109',
      },
    },
  ]);
  const menuItems = createdCafes.flatMap(cafe =>
    menuForCafe(cafe).map(([name, price, category, description, isVeg], index) => ({
      cafeId: cafe._id,
      vendorId: cafe.vendorId,
      name,
      price,
      category,
      description,
      image: cafe.image,
      imageType: 'asset',
      isVeg,
      rating: 4.3 + (index % 5) / 10,
      reviews: 80 + index * 35,
    }))
  );

  await MenuItem.insertMany(menuItems);
  console.log(`Seeded ${createdCafes.length} cafes, ${menuItems.length} menu items, 1 customer, and 1 vendor`);
}

seed()
  .catch(err => {
    console.error(err);
    process.exitCode = 1;
  })
  .finally(() => mongoose.disconnect());
