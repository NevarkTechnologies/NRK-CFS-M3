# Vendor-Cafeteria Relationship Guide

## Overview
This document explains how vendors are connected to cafeterias in the Nevark Food App. The system uses MongoDB references to establish proper relationships between vendors (Users with role='vendor') and cafeterias (Cafe documents).

## Data Models

### User Model
```javascript
{
  googleId: String,
  name: String,
  email: String,
  avatar: String,
  role: ['customer' | 'vendor' | 'admin'],  // Identifies the user type
  cafeId: ObjectId (ref: Cafe),              // References the cafeteria they manage
  address: {...},
  paymentLabel: String,
  timestamps: true
}
```

### Cafe Model
```javascript
{
  name: String,
  slug: String,
  cuisine: String,
  vendorId: ObjectId (ref: User),            // References the vendor who manages this cafe
  legacyVendorId: String,                    // For backwards compatibility
  rating: Number,
  reviews: Number,
  active: Boolean,
  timestamps: true
}
```

### MenuItem Model
```javascript
{
  cafeId: ObjectId (ref: Cafe),              // Which cafeteria this item belongs to
  vendorId: ObjectId (ref: User),            // Which vendor created this item
  legacyVendorId: String,                    // For backwards compatibility
  name: String,
  price: Number,
  category: String,
  available: Boolean,
  timestamps: true
}
```

## API Endpoints

### 1. Assign a Cafeteria to a Vendor
**Endpoint:** `POST /api/vendors/:vendorId/assign-cafe`

**Description:** Links a vendor to a cafeteria. This creates a bidirectional relationship:
- Updates the Cafe's `vendorId` to point to the User
- Updates the User's `cafeId` to point to the Cafe

**Request Body:**
```json
{
  "cafeId": "ObjectId of the cafeteria"
}
```

**Example:**
```bash
curl -X POST http://localhost:5000/api/vendors/USER_ID/assign-cafe \
  -H "Content-Type: application/json" \
  -d '{"cafeId": "CAFE_ID"}'
```

**Response:**
```json
{
  "message": "Vendor successfully assigned to cafeteria",
  "vendor": {
    "_id": "USER_ID",
    "name": "John Vendor",
    "email": "vendor@example.com",
    "cafeId": {
      "_id": "CAFE_ID",
      "name": "Coffee House",
      "slug": "coffee-house"
    }
  },
  "cafe": {
    "_id": "CAFE_ID",
    "name": "Coffee House",
    "vendorId": {
      "_id": "USER_ID",
      "name": "John Vendor",
      "email": "vendor@example.com",
      "avatar": "..."
    }
  }
}
```

---

### 2. Get Vendor's Assigned Cafeteria
**Endpoint:** `GET /api/vendors/:vendorId/cafes`

**Description:** Retrieves the cafeteria assigned to a specific vendor

**Example:**
```bash
curl http://localhost:5000/api/vendors/USER_ID/cafes
```

**Response:**
```json
{
  "message": "Vendor cafeteria found",
  "cafe": {
    "_id": "CAFE_ID",
    "name": "Coffee House",
    "slug": "coffee-house",
    "cuisine": "Beverages",
    "rating": 4.5,
    "vendorId": "USER_ID"
  }
}
```

If no cafeteria is assigned:
```json
{
  "message": "Vendor has no assigned cafeteria",
  "cafe": null
}
```

---

### 3. Get Vendor for a Cafeteria
**Endpoint:** `GET /api/cafes/:cafeId/vendor`

**Description:** Retrieves the vendor responsible for a specific cafeteria

**Example:**
```bash
curl http://localhost:5000/api/cafes/CAFE_ID/vendor
```

**Response:**
```json
{
  "message": "Vendor found for cafeteria",
  "vendor": {
    "_id": "USER_ID",
    "name": "John Vendor",
    "email": "vendor@example.com",
    "avatar": "..."
  }
}
```

---

### 4. Remove Vendor from Cafeteria (Unassign)
**Endpoint:** `DELETE /api/vendors/:vendorId/cafes/:cafeId`

**Description:** Removes the relationship between a vendor and cafeteria

**Example:**
```bash
curl -X DELETE http://localhost:5000/api/vendors/USER_ID/cafes/CAFE_ID
```

**Response:**
```json
{
  "message": "Vendor successfully unassigned from cafeteria",
  "vendor": {
    "_id": "USER_ID",
    "cafeId": null
  },
  "cafe": {
    "_id": "CAFE_ID",
    "vendorId": null
  }
}
```

---

### 5. Get Menu Items for a Vendor
**Endpoint:** `GET /api/vendors/:vendorId/menu`

**Description:** Retrieves all menu items created by a specific vendor

**Example:**
```bash
curl http://localhost:5000/api/vendors/USER_ID/menu
```

**Response:**
```json
{
  "message": "Menu items found",
  "items": [
    {
      "_id": "ITEM_ID",
      "name": "Espresso",
      "price": 150,
      "category": "Coffee",
      "cafeId": {
        "_id": "CAFE_ID",
        "name": "Coffee House"
      },
      "vendorId": "USER_ID"
    }
  ]
}
```

---

### 6. Get Menu Items for a Cafeteria
**Endpoint:** `GET /api/cafes/:cafeId/menu`

**Description:** Retrieves all available menu items for a cafeteria

**Example:**
```bash
curl http://localhost:5000/api/cafes/CAFE_ID/menu
```

---

## Google Firebase Authentication Flow

When a vendor logs in via Google Firebase:

1. **Login:** User authenticates with Google
2. **Auto-linking:** The system automatically checks if the vendor has a cafeteria assigned
3. **Relationship:** If assigned, the User's `cafeId` is populated with their cafeteria
4. **Response:** The user object is returned with the cafeteria information populated

```javascript
// In /api/auth/google endpoint:
if (user.role === 'vendor' && user._id && !user.cafeId) {
  const cafe = await Cafe.findOne({ vendorId: user._id });
  if (cafe) {
    user = await User.findByIdAndUpdate(
      user._id,
      { cafeId: cafe._id },
      { new: true }
    ).populate('cafeId');
  }
}
```

---

## Usage Scenarios

### Scenario 1: Creating a Vendor and Assigning a Cafeteria

```bash
# Step 1: Vendor logs in via Google (auto-creates User with role='vendor')
POST /api/auth/google
{
  "googleId": "google123",
  "name": "John Vendor",
  "email": "vendor@example.com",
  "avatar": "..."
}

# Step 2: Create a cafeteria
POST /api/cafes
{
  "name": "Coffee House",
  "slug": "coffee-house",
  "cuisine": "Beverages",
  "location": "Downtown"
}

# Step 3: Assign the cafeteria to the vendor
POST /api/vendors/USER_ID/assign-cafe
{
  "cafeId": "CAFE_ID"
}
```

### Scenario 2: Vendor Adding Menu Items

```bash
# After assignment, vendor can add menu items to their cafeteria
POST /api/menu
{
  "cafeId": "CAFE_ID",
  "vendorId": "USER_ID",
  "name": "Espresso",
  "price": 150,
  "category": "Coffee",
  "isVeg": true
}
```

### Scenario 3: Customer Viewing Cafeteria and Its Menu

```bash
# Get all cafeterias
GET /api/cafes

# Get menu for a specific cafeteria (with vendor info populated)
GET /api/cafes/CAFE_ID/menu

# Get vendor details for the cafeteria
GET /api/cafes/CAFE_ID/vendor
```

---

## Backwards Compatibility

The system supports legacy data:
- `Cafe.legacyVendorId` - Stores old string vendor IDs
- `MenuItem.legacyVendorId` - Stores old string vendor IDs
- Menu queries automatically handle both ObjectId and string vendorIds

When querying menu items by vendorId:
```bash
# Works with ObjectId
GET /api/menu?vendorId=USER_OBJECT_ID

# Also works with legacy string IDs
GET /api/menu?vendorId=ADMIN_01
```

---

## Important Notes

1. **Bidirectional Relationship:** When you assign a vendor to a cafeteria, both sides are updated:
   - `User.cafeId` → points to Cafe
   - `Cafe.vendorId` → points to User

2. **Data Integrity:** Always use the assignment endpoint to create relationships, not direct updates

3. **Firebase Integration:** The system automatically populates vendor-cafe relationships when vendors log in via Google Firebase

4. **Menu Items:** Always include `cafeId` and `vendorId` when creating menu items

5. **Cascading:** If you need to delete a vendor, make sure to unassign their cafeteria first

---

## Testing

### Using Postman or similar tools:

1. **Test Assignment:**
   ```
   POST http://localhost:5000/api/vendors/{vendorId}/assign-cafe
   Body: {"cafeId": "{cafeId}"}
   ```

2. **Verify Relationship:**
   ```
   GET http://localhost:5000/api/vendors/{vendorId}/cafes
   GET http://localhost:5000/api/cafes/{cafeId}/vendor
   ```

3. **Get Vendor's Menu:**
   ```
   GET http://localhost:5000/api/vendors/{vendorId}/menu
   ```

---

## Future Enhancements

- [ ] Multiple cafeterias per vendor
- [ ] Vendor management dashboard
- [ ] Analytics per vendor/cafeteria
- [ ] Vendor profile management
- [ ] Role-based access control for API endpoints
