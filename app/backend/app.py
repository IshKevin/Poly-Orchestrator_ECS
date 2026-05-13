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


def init_db():
    try:
        conn = get_db()
        with conn.cursor() as cur:
            cur.execute(
                """
                CREATE TABLE IF NOT EXISTS products (
                    id     SERIAL PRIMARY KEY,
                    name   VARCHAR(255) NOT NULL,
                    description TEXT,
                    price  NUMERIC(10, 2) NOT NULL,
                    stock  INTEGER DEFAULT 0,
                    category VARCHAR(100)
                )
                """
            )
            cur.execute("SELECT COUNT(*) FROM products")
            if cur.fetchone()[0] == 0:
                sample = [
                    ("Laptop Pro 15", "High-performance laptop for professionals", 1299.99, 50, "Electronics"),
                    ("Wireless Mouse", "Ergonomic wireless mouse with USB receiver", 29.99, 200, "Accessories"),
                    ("USB-C Hub 7-in-1", "7-port USB-C hub with HDMI and PD", 49.99, 150, "Accessories"),
                    ("Mechanical Keyboard", "TKL RGB mechanical keyboard, Cherry MX", 89.99, 100, "Accessories"),
                    ("4K Monitor 27\"", "27-inch IPS 4K UHD monitor, 60Hz", 399.99, 30, "Electronics"),
                    ("Noise-Cancelling Headphones", "Over-ear ANC headphones, 30hr battery", 249.99, 75, "Audio"),
                    ("Portable SSD 1TB", "USB 3.2 Gen 2 portable SSD, 1050MB/s", 119.99, 120, "Storage"),
                    ("Webcam 1080p", "Full HD webcam with built-in mic", 79.99, 90, "Accessories"),
                ]
                psycopg2.extras.execute_values(
                    cur,
                    "INSERT INTO products (name, description, price, stock, category) VALUES %s",
                    sample,
                )
        conn.commit()
        conn.close()
        logger.info("Database initialized successfully")
    except Exception as exc:
        logger.error("DB init error: %s", exc)


# ── Health ──────────────────────────────────────────────────────────────────

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


# ── Products ─────────────────────────────────────────────────────────────────

@app.route("/api/products")
def list_products():
    try:
        conn = get_db()
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute("SELECT id, name, description, price, stock, category FROM products ORDER BY id")
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
                "SELECT id, name, description, price, stock, category FROM products WHERE id = %s",
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


# ── Cart (Redis) ──────────────────────────────────────────────────────────────

@app.route("/api/cart/<session_id>")
def get_cart(session_id):
    try:
        raw = redis_client.get(f"cart:{session_id}")
        cart = json.loads(raw) if raw else []
        return jsonify({"session_id": session_id, "cart": cart, "item_count": len(cart)})
    except Exception as exc:
        logger.error("get_cart error: %s", exc)
        return jsonify({"error": "Unable to fetch cart"}), 500


@app.route("/api/cart/<session_id>", methods=["POST"])
def add_to_cart(session_id):
    try:
        item = request.get_json(force=True)
        if not item or "product_id" not in item:
            return jsonify({"error": "product_id is required"}), 400

        raw = redis_client.get(f"cart:{session_id}")
        cart = json.loads(raw) if raw else []

        existing = next((i for i in cart if i["product_id"] == item["product_id"]), None)
        if existing:
            existing["quantity"] = existing.get("quantity", 1) + item.get("quantity", 1)
        else:
            item.setdefault("quantity", 1)
            cart.append(item)

        redis_client.setex(f"cart:{session_id}", 3600, json.dumps(cart))
        return jsonify({"session_id": session_id, "cart": cart, "item_count": len(cart)})
    except Exception as exc:
        logger.error("add_to_cart error: %s", exc)
        return jsonify({"error": "Unable to update cart"}), 500


@app.route("/api/cart/<session_id>", methods=["DELETE"])
def clear_cart(session_id):
    try:
        redis_client.delete(f"cart:{session_id}")
        return jsonify({"session_id": session_id, "message": "Cart cleared"})
    except Exception as exc:
        logger.error("clear_cart error: %s", exc)
        return jsonify({"error": "Unable to clear cart"}), 500


if __name__ == "__main__":
    init_db()
    app.run(host="0.0.0.0", port=5000, debug=os.environ.get("DEBUG", "false").lower() == "true")
else:
    init_db()
