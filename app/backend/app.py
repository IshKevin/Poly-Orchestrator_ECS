import os
import json
import logging
from flask import Flask, jsonify, request
from flask_cors import CORS
import psycopg2
import psycopg2.extras
import redis

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)
CORS(app)

redis_client = redis.Redis(
    host=os.environ.get("REDIS_HOST", "redis"),
    port=int(os.environ.get("REDIS_PORT", 6379)),
    decode_responses=True,
    socket_connect_timeout=3,
    socket_timeout=3,
)


def get_db():
    return psycopg2.connect(
        host=os.environ.get("DB_HOST", "postgres"),
        port=int(os.environ.get("DB_PORT", 5432)),
        dbname=os.environ.get("DB_NAME", "shopnow"),
        user=os.environ.get("DB_USER", "shopnow"),
        password=os.environ.get("DB_PASSWORD", "shopnow123"),
        connect_timeout=5,
    )


SEED_PRODUCTS = [
    ("Laptop Pro 15", "High-performance 16GB RAM 512GB SSD Intel i7", 1299.99, 1499.99, 50, "Electronics", "laptop15", 4.8, 2341, "Sale"),
    ("Wireless Mouse Pro", "Ergonomic 2.4GHz 2-year battery", 29.99, None, 200, "Accessories", "wmousepro", 4.5, 876, None),
    ("USB-C Hub 7-in-1", "7-port HDMI 4K 100W PD 3xUSB3.0", 49.99, 69.99, 150, "Accessories", "usbhub7", 4.6, 1203, "Sale"),
    ("Mechanical Keyboard TKL", "RGB Cherry MX Red switches", 89.99, None, 100, "Accessories", "mechkbd", 4.7, 3102, "New"),
    ("4K Monitor 27in", "IPS 4K 60Hz 99% sRGB USB-C", 399.99, 449.99, 30, "Electronics", "mon27k", 4.9, 1540, "Sale"),
    ("Noise-Cancelling Headphones", "Over-ear ANC 30hr battery foldable", 249.99, 299.99, 75, "Audio", "anc_hdp", 4.8, 4210, "Sale"),
    ("Portable SSD 1TB", "USB 3.2 Gen2 1050MB/s read", 119.99, None, 120, "Storage", "pssd1tb", 4.7, 987, None),
    ("Webcam 4K", "4K 30fps ring light noise-cancelling mic", 129.99, 159.99, 90, "Accessories", "webcam4k", 4.6, 654, "New"),
    ("True Wireless Earbuds", "ANC 36hr total battery IPX5", 159.99, 199.99, 200, "Audio", "twe_anc", 4.7, 5632, "Sale"),
    ("Smart Watch Series 8", "GPS ECG blood oxygen sleep tracking", 349.99, None, 60, "Electronics", "swatch8", 4.9, 8901, "New"),
    ("iPad Pro 11in", "M2 chip Liquid Retina 5G 256GB", 899.99, 999.99, 40, "Electronics", "ipadpro11", 4.9, 2134, "Sale"),
    ("Gaming Mouse RGB", "16000 DPI 11 buttons RGB lighting", 59.99, 79.99, 180, "Gaming", "gmousergb", 4.6, 1872, "Sale"),
    ("Bluetooth Speaker 360", "360 surround IPX7 waterproof 24hr", 79.99, None, 110, "Audio", "btspeaker", 4.5, 2341, None),
    ("USB Flash Drive 256GB", "USB 3.2 150MB/s retractable", 24.99, 34.99, 500, "Storage", "usb256gb", 4.4, 3201, "Sale"),
    ("Wireless Charging Pad 15W", "Fast charge iPhone Android", 34.99, None, 250, "Accessories", "wirelesspad", 4.3, 765, "New"),
    ("Gaming Headset 7.1", "7.1 surround retractable mic memory foam", 99.99, 129.99, 85, "Gaming", "ghs71", 4.7, 2100, "Sale"),
]


def init_db():
    try:
        conn = get_db()
        with conn.cursor() as cur:
            cur.execute(
                """
                CREATE TABLE IF NOT EXISTS products (
                    id             SERIAL PRIMARY KEY,
                    name           VARCHAR(255) NOT NULL,
                    description    TEXT,
                    price          NUMERIC(10,2) NOT NULL,
                    stock          INTEGER DEFAULT 0,
                    category       VARCHAR(100)
                )
                """
            )

            for col, coltype in [
                ("original_price", "NUMERIC(10,2)"),
                ("image_url", "TEXT"),
                ("rating", "NUMERIC(2,1)"),
                ("review_count", "INTEGER"),
                ("badge", "VARCHAR(50)"),
            ]:
                cur.execute(
                    f"ALTER TABLE products ADD COLUMN IF NOT EXISTS {col} {coltype}"
                )

            cur.execute(
                """
                CREATE TABLE IF NOT EXISTS orders (
                    id         SERIAL PRIMARY KEY,
                    session_id VARCHAR(255) NOT NULL,
                    items      JSONB NOT NULL,
                    total      NUMERIC(10,2) NOT NULL,
                    status     VARCHAR(50) DEFAULT 'confirmed',
                    created_at TIMESTAMP DEFAULT NOW()
                )
                """
            )

            cur.execute("SELECT COUNT(*) FROM products WHERE image_url IS NULL")
            needs_seed = cur.fetchone()[0] > 0

            cur.execute("SELECT COUNT(*) FROM products")
            is_empty = cur.fetchone()[0] == 0

            if is_empty or needs_seed:
                cur.execute("TRUNCATE products RESTART IDENTITY")
                rows = [
                    (
                        name, desc, price, original_price, stock, category,
                        f"https://picsum.photos/seed/{image_seed}/400/300",
                        rating, review_count, badge,
                    )
                    for name, desc, price, original_price, stock, category, image_seed, rating, review_count, badge
                    in SEED_PRODUCTS
                ]
                psycopg2.extras.execute_values(
                    cur,
                    """
                    INSERT INTO products
                        (name, description, price, original_price, stock, category, image_url, rating, review_count, badge)
                    VALUES %s
                    """,
                    rows,
                )

        conn.commit()
        conn.close()
        logger.info("Database initialized successfully")
    except Exception as exc:
        logger.error("DB init error: %s", exc)


# ── Health ───────────────────────────────────────────────────────────────────

@app.route("/api/health")
def health():
    checks = {"database": "ok", "redis": "ok"}
    status = 200

    try:
        conn = get_db()
        conn.close()
    except Exception as exc:
        checks["database"] = str(exc)
        status = 503

    try:
        redis_client.ping()
    except Exception as exc:
        checks["redis"] = str(exc)
        status = 503

    return jsonify({"status": "healthy" if status == 200 else "degraded", "checks": checks}), status


# ── Products ──────────────────────────────────────────────────────────────────

@app.route("/api/products")
def list_products():
    try:
        category = request.args.get("category", "").strip()
        search = request.args.get("search", "").strip()

        query = """
            SELECT id, name, description, price, original_price, stock, category,
                   image_url, rating, review_count, badge
            FROM products
        """
        conditions = []
        params = []

        if category and category.lower() != "all":
            conditions.append("category = %s")
            params.append(category)

        if search:
            conditions.append("(name ILIKE %s OR description ILIKE %s)")
            params.extend([f"%{search}%", f"%{search}%"])

        if conditions:
            query += " WHERE " + " AND ".join(conditions)

        query += " ORDER BY id"

        conn = get_db()
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute(query, params)
            rows = cur.fetchall()
        conn.close()
        return jsonify({"products": [dict(r) for r in rows]})
    except Exception as exc:
        logger.error("list_products error: %s", exc)
        return jsonify({"error": "Unable to fetch products"}), 500


@app.route("/api/products/<int:product_id>")
def get_product(product_id):
    try:
        conn = get_db()
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute(
                """
                SELECT id, name, description, price, original_price, stock, category,
                       image_url, rating, review_count, badge
                FROM products WHERE id = %s
                """,
                (product_id,),
            )
            row = cur.fetchone()
        conn.close()
        if row is None:
            return jsonify({"error": "Product not found"}), 404
        return jsonify(dict(row))
    except Exception as exc:
        logger.error("get_product error: %s", exc)
        return jsonify({"error": "Unable to fetch product"}), 500


@app.route("/api/categories")
def list_categories():
    try:
        conn = get_db()
        with conn.cursor() as cur:
            cur.execute("SELECT DISTINCT category FROM products WHERE category IS NOT NULL ORDER BY category")
            rows = cur.fetchall()
        conn.close()
        categories = ["All"] + [r[0] for r in rows]
        return jsonify({"categories": categories})
    except Exception as exc:
        logger.error("list_categories error: %s", exc)
        return jsonify({"error": "Unable to fetch categories"}), 500


# ── Cart (Redis) ───────────────────────────────────────────────────────────────

def _cart_key(session_id):
    return f"cart:{session_id}"


def _sum_quantities(cart):
    return sum(i.get("quantity", 1) for i in cart)


@app.route("/api/cart/<session_id>")
def get_cart(session_id):
    try:
        raw = redis_client.get(_cart_key(session_id))
        cart = json.loads(raw) if raw else []
        return jsonify({"session_id": session_id, "cart": cart, "item_count": _sum_quantities(cart)})
    except Exception as exc:
        logger.error("get_cart error: %s", exc)
        return jsonify({"error": "Unable to fetch cart"}), 500


@app.route("/api/cart/<session_id>", methods=["POST"])
def add_to_cart(session_id):
    try:
        item = request.get_json(force=True)
        if not item or "product_id" not in item:
            return jsonify({"error": "product_id is required"}), 400

        raw = redis_client.get(_cart_key(session_id))
        cart = json.loads(raw) if raw else []

        existing = next((i for i in cart if i["product_id"] == item["product_id"]), None)
        if existing:
            existing["quantity"] = existing.get("quantity", 1) + item.get("quantity", 1)
        else:
            item.setdefault("quantity", 1)
            cart.append(item)

        redis_client.setex(_cart_key(session_id), 3600 * 24, json.dumps(cart))
        return jsonify({"session_id": session_id, "cart": cart, "item_count": _sum_quantities(cart)})
    except Exception as exc:
        logger.error("add_to_cart error: %s", exc)
        return jsonify({"error": "Unable to update cart"}), 500


@app.route("/api/cart/<session_id>/item/<int:product_id>", methods=["PUT"])
def update_cart_item(session_id, product_id):
    try:
        body = request.get_json(force=True)
        quantity = body.get("quantity", 1) if body else 1

        raw = redis_client.get(_cart_key(session_id))
        cart = json.loads(raw) if raw else []

        if quantity <= 0:
            cart = [i for i in cart if i["product_id"] != product_id]
        else:
            existing = next((i for i in cart if i["product_id"] == product_id), None)
            if existing:
                existing["quantity"] = quantity
            else:
                return jsonify({"error": "Item not in cart"}), 404

        redis_client.setex(_cart_key(session_id), 3600 * 24, json.dumps(cart))
        return jsonify({"session_id": session_id, "cart": cart, "item_count": _sum_quantities(cart)})
    except Exception as exc:
        logger.error("update_cart_item error: %s", exc)
        return jsonify({"error": "Unable to update cart item"}), 500


@app.route("/api/cart/<session_id>", methods=["DELETE"])
def clear_cart(session_id):
    try:
        redis_client.delete(_cart_key(session_id))
        return jsonify({"session_id": session_id, "message": "Cart cleared"})
    except Exception as exc:
        logger.error("clear_cart error: %s", exc)
        return jsonify({"error": "Unable to clear cart"}), 500


# ── Orders ────────────────────────────────────────────────────────────────────

@app.route("/api/orders/<session_id>", methods=["POST"])
def place_order(session_id):
    try:
        raw = redis_client.get(_cart_key(session_id))
        cart = json.loads(raw) if raw else []

        if not cart:
            return jsonify({"error": "Cart is empty"}), 400

        total = sum(float(i.get("price", 0)) * int(i.get("quantity", 1)) for i in cart)

        conn = get_db()
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute(
                """
                INSERT INTO orders (session_id, items, total)
                VALUES (%s, %s, %s)
                RETURNING id, session_id, items, total, status, created_at
                """,
                (session_id, json.dumps(cart), total),
            )
            order = dict(cur.fetchone())
        conn.commit()
        conn.close()

        redis_client.delete(_cart_key(session_id))

        order["items"] = cart
        return jsonify({"order": order}), 201
    except Exception as exc:
        logger.error("place_order error: %s", exc)
        return jsonify({"error": "Unable to place order"}), 500


@app.route("/api/orders/<session_id>")
def list_orders(session_id):
    try:
        conn = get_db()
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute(
                """
                SELECT id, session_id, items, total, status, created_at
                FROM orders
                WHERE session_id = %s
                ORDER BY created_at DESC
                LIMIT 10
                """,
                (session_id,),
            )
            rows = cur.fetchall()
        conn.close()
        orders = []
        for r in rows:
            o = dict(r)
            if isinstance(o["items"], str):
                o["items"] = json.loads(o["items"])
            orders.append(o)
        return jsonify({"orders": orders})
    except Exception as exc:
        logger.error("list_orders error: %s", exc)
        return jsonify({"error": "Unable to fetch orders"}), 500


if __name__ == "__main__":
    init_db()
    app.run(host="0.0.0.0", port=5000, debug=os.environ.get("DEBUG", "false").lower() == "true")
else:
    init_db()
