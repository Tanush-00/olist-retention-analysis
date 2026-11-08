-- =====================================================================
-- 01_schema.sql
-- Olist Brazilian E-commerce database schema (SQLite)
--
-- 9 source tables, loaded from the raw Kaggle CSVs by scripts/load_data.py.
-- Timestamps are stored as ISO text ('YYYY-MM-DD HH:MM:SS'), which SQLite's
-- date functions (DATE, strftime, julianday) understand directly.
--
-- Foreign keys are declared for documentation; orphan rows are checked
-- explicitly in 02_data_quality.sql instead of being enforced at load time.
-- =====================================================================

DROP TABLE IF EXISTS customers;
CREATE TABLE customers (
    customer_id              TEXT PRIMARY KEY,   -- NOTE: one id per ORDER
    customer_unique_id       TEXT NOT NULL,      -- the real person (use for retention)
    customer_zip_code_prefix TEXT,
    customer_city            TEXT,
    customer_state           TEXT
);

DROP TABLE IF EXISTS sellers;
CREATE TABLE sellers (
    seller_id              TEXT PRIMARY KEY,
    seller_zip_code_prefix TEXT,
    seller_city            TEXT,
    seller_state           TEXT
);

DROP TABLE IF EXISTS category_translation;
CREATE TABLE category_translation (
    product_category_name         TEXT PRIMARY KEY,
    product_category_name_english TEXT
);

DROP TABLE IF EXISTS products;
CREATE TABLE products (
    product_id                 TEXT PRIMARY KEY,
    product_category_name      TEXT REFERENCES category_translation (product_category_name),
    product_name_lenght        INTEGER,          -- (sic) original column spelling
    product_description_lenght INTEGER,
    product_photos_qty         INTEGER,
    product_weight_g           REAL,
    product_length_cm          REAL,
    product_height_cm          REAL,
    product_width_cm           REAL
);

DROP TABLE IF EXISTS orders;
CREATE TABLE orders (
    order_id                      TEXT PRIMARY KEY,
    customer_id                   TEXT NOT NULL REFERENCES customers (customer_id),
    order_status                  TEXT NOT NULL,
    order_purchase_timestamp      TEXT NOT NULL,
    order_approved_at             TEXT,
    order_delivered_carrier_date  TEXT,
    order_delivered_customer_date TEXT,
    order_estimated_delivery_date TEXT
);

DROP TABLE IF EXISTS order_items;
CREATE TABLE order_items (
    order_id            TEXT    NOT NULL REFERENCES orders (order_id),
    order_item_id       INTEGER NOT NULL,        -- 1, 2, 3 ... within an order
    product_id          TEXT    NOT NULL REFERENCES products (product_id),
    seller_id           TEXT    NOT NULL REFERENCES sellers (seller_id),
    shipping_limit_date TEXT,
    price               REAL,
    freight_value       REAL,
    PRIMARY KEY (order_id, order_item_id)
);

DROP TABLE IF EXISTS order_payments;
CREATE TABLE order_payments (
    order_id             TEXT    NOT NULL REFERENCES orders (order_id),
    payment_sequential   INTEGER NOT NULL,
    payment_type         TEXT,
    payment_installments INTEGER,
    payment_value        REAL,
    PRIMARY KEY (order_id, payment_sequential)
);

-- No primary key: review_id is NOT unique in the source data (see 02_data_quality.sql)
DROP TABLE IF EXISTS order_reviews;
CREATE TABLE order_reviews (
    review_id               TEXT NOT NULL,
    order_id                TEXT NOT NULL REFERENCES orders (order_id),
    review_score            INTEGER,
    review_comment_title    TEXT,
    review_comment_message  TEXT,
    review_creation_date    TEXT,
    review_answer_timestamp TEXT
);

-- No primary key: ~1M rows with many exact duplicates per zip prefix
DROP TABLE IF EXISTS geolocation;
CREATE TABLE geolocation (
    geolocation_zip_code_prefix TEXT,
    geolocation_lat             REAL,
    geolocation_lng             REAL,
    geolocation_city            TEXT,
    geolocation_state           TEXT
);

-- Indexes for the joins used in the analysis
CREATE INDEX idx_customers_unique ON customers (customer_unique_id);
CREATE INDEX idx_orders_customer  ON orders (customer_id);
CREATE INDEX idx_items_product    ON order_items (product_id);
CREATE INDEX idx_items_seller     ON order_items (seller_id);
CREATE INDEX idx_reviews_order    ON order_reviews (order_id);
CREATE INDEX idx_geo_zip          ON geolocation (geolocation_zip_code_prefix);
