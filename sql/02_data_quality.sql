-- =====================================================================
-- 02_data_quality.sql
-- Data quality audit: row counts, missing values, duplicates, orphans,
-- impossible dates. Run BEFORE any analysis so the caveats are known.
--
-- Each block starting with "-- name:" is run by scripts/run_sql.py and
-- its result is saved to outputs/sql_results/02_data_quality__<name>.csv
-- =====================================================================

-- name: row_counts
SELECT 'customers'            AS table_name, COUNT(*) AS row_count FROM customers
UNION ALL SELECT 'orders',               COUNT(*) FROM orders
UNION ALL SELECT 'order_items',          COUNT(*) FROM order_items
UNION ALL SELECT 'order_payments',       COUNT(*) FROM order_payments
UNION ALL SELECT 'order_reviews',        COUNT(*) FROM order_reviews
UNION ALL SELECT 'products',             COUNT(*) FROM products
UNION ALL SELECT 'sellers',              COUNT(*) FROM sellers
UNION ALL SELECT 'category_translation', COUNT(*) FROM category_translation
UNION ALL SELECT 'geolocation',          COUNT(*) FROM geolocation;

-- name: order_status_breakdown
SELECT order_status,
       COUNT(*)                                            AS orders,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_orders
FROM orders
GROUP BY order_status
ORDER BY orders DESC;

-- name: orders_missing_values
SELECT COUNT(*)                                                   AS total_orders,
       SUM(order_approved_at IS NULL)                             AS missing_approved_at,
       SUM(order_delivered_carrier_date IS NULL)                  AS missing_carrier_date,
       SUM(order_delivered_customer_date IS NULL)                 AS missing_delivered_date,
       SUM(order_status = 'delivered'
           AND order_delivered_customer_date IS NULL)             AS delivered_but_no_date,
       SUM(order_status <> 'delivered'
           AND order_delivered_customer_date IS NOT NULL)         AS not_delivered_but_has_date
FROM orders;

-- name: integrity_checks
SELECT 'customers: person with >1 customer_id (repeat buyers)' AS check_name,
       COUNT(*) AS affected
FROM (SELECT customer_unique_id FROM customers
      GROUP BY customer_unique_id HAVING COUNT(*) > 1)
UNION ALL
SELECT 'reviews: duplicate review_id',
       COUNT(*) - COUNT(DISTINCT review_id) FROM order_reviews
UNION ALL
SELECT 'reviews: orders with more than one review',
       COUNT(*) FROM (SELECT order_id FROM order_reviews
                      GROUP BY order_id HAVING COUNT(*) > 1)
UNION ALL
SELECT 'orders: no review at all',
       COUNT(*) FROM orders o
       WHERE NOT EXISTS (SELECT 1 FROM order_reviews r WHERE r.order_id = o.order_id)
UNION ALL
SELECT 'orders: no items',
       COUNT(*) FROM orders o
       WHERE NOT EXISTS (SELECT 1 FROM order_items i WHERE i.order_id = o.order_id)
UNION ALL
SELECT 'orders: no payment',
       COUNT(*) FROM orders o
       WHERE NOT EXISTS (SELECT 1 FROM order_payments p WHERE p.order_id = o.order_id)
UNION ALL
SELECT 'order_items: product not in products table',
       COUNT(*) FROM order_items i
       WHERE NOT EXISTS (SELECT 1 FROM products p WHERE p.product_id = i.product_id)
UNION ALL
SELECT 'products: missing category',
       COUNT(*) FROM products WHERE product_category_name IS NULL
UNION ALL
SELECT 'products: category without English translation',
       COUNT(DISTINCT p.product_category_name)
       FROM products p
       LEFT JOIN category_translation t
              ON t.product_category_name = p.product_category_name
       WHERE p.product_category_name IS NOT NULL
         AND t.product_category_name IS NULL
UNION ALL
SELECT 'orders: delivered before purchase (impossible)',
       COUNT(*) FROM orders
       WHERE order_delivered_customer_date < order_purchase_timestamp
UNION ALL
SELECT 'orders: handed to carrier before purchase (impossible)',
       COUNT(*) FROM orders
       WHERE order_delivered_carrier_date < order_purchase_timestamp
UNION ALL
SELECT 'payments: zero payment value',
       COUNT(*) FROM order_payments WHERE payment_value = 0
UNION ALL
SELECT 'geolocation: exact duplicate rows',
       (SELECT COUNT(*) FROM geolocation)
     - (SELECT COUNT(*) FROM (SELECT DISTINCT * FROM geolocation));

-- name: orders_per_month
-- Shows why trends are limited to Jan-2017 .. Aug-2018 (thin edges)
SELECT strftime('%Y-%m', order_purchase_timestamp) AS purchase_month,
       COUNT(*)                                    AS orders
FROM orders
GROUP BY purchase_month
ORDER BY purchase_month;
