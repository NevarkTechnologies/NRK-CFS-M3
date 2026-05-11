# Nevark Food App Backend

Express + MongoDB API for the Flutter food ordering flow.

## Setup

1. Create `Backend/.env` from `.env.example`.
2. Put your MongoDB connection string in `MONGO_URI`.
3. Run:

```bash
npm install
npm run seed
npm start
```

The API runs on `http://localhost:5000` by default.

## Main Routes

- `GET /api/health`
- `POST /api/auth/google`
- `GET /api/cafes`
- `GET /api/cafes/:id/menu`
- `GET /api/menu`
- `POST /api/menu`
- `PATCH /api/menu/:id`
- `DELETE /api/menu/:id`
- `POST /api/orders`
- `GET /api/orders`
- `GET /api/orders/:orderId`
- `PATCH /api/orders/:orderId/status`
- `GET /api/vendor/:vendorId/dashboard`
