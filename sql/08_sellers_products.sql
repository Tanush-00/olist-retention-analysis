-- =====================================================================
-- 08_sellers_products.sql
-- Which categories drive revenue, which ones disappoint customers, and
-- which sellers cause most of the late deliveries.
-- =====================================================================

-- name: top_categories
SELECT COALESCE(t.product_category_name_english,
                p.product_category_name, 'unknown')  AS category,
       COUNT(DISTINCT i.order_id)                    AS orders,
       ROUND(SUM(i.price), 0)                        AS product_revenue,
       ROUND(100.0 * SUM(i.price) / SUM(SUM(i.price)) OVER (), 1) AS pct_revenue,
       ROUND(AVG(i.price), 2)                        AS avg_item_price,
       ROUND(AVG(o.review_score), 2)                 AS avg_review_score,
       ROUND(100.0 * AVG(o.is_late), 1)              AS late_pct
FROM order_items i
JOIN v_orders o  ON o.order_id  = i.order_id
JOIN products p  ON p.product_id = i.product_id
LEFT JOIN category_translation t ON t.product_category_name = p.product_category_name
GROUP BY category
ORDER BY product_revenue DESC
LIMIT 15;

-- name: lowest_rated_categories
-- Categories with at least 500 orders, ranked by average review
SELECT COALESCE(t.product_category_name_english,
                p.product_category_name, 'unknown')  AS category,
       COUNT(DISTINCT i.order_id)                    AS orders,
       ROUND(AVG(o.review_score), 2)                 AS avg_review_score,
       ROUND(100.0 * AVG(o.review_score <= 2), 1)    AS pct_1_2_star,
       ROUND(100.0 * AVG(o.is_late), 1)              AS late_pct
FROM order_items i
JOIN v_orders o  ON o.order_id  = i.order_id
JOIN products p  ON p.product_id = i.product_id
LEFT JOIN category_translation t ON t.product_category_name = p.product_category_name
WHERE o.review_score IS NOT NULL
GROUP BY category
HAVING COUNT(DISTINCT i.order_id) >= 500
ORDER BY avg_review_score
LIMIT 10;

-- name: seller_revenue_concentration
-- Pareto check: how much revenue do the top 10% / 20% of sellers bring?
WITH seller_rev AS (
    SELECT i.seller_id, SUM(i.price) AS revenue
    FROM order_items i
    JOIN v_orders o ON o.order_id = i.order_id
    GROUP BY i.seller_id
),
ranked AS (
    SELECT seller_id, revenue,
           NTILE(10) OVER (ORDER BY revenue DESC) AS decile
    FROM seller_rev
)
SELECT decile                                                    AS seller_decile,
       COUNT(*)                                                  AS sellers,
       ROUND(SUM(revenue), 0)                                    AS revenue,
       ROUND(100.0 * SUM(revenue) / SUM(SUM(revenue)) OVER (), 1) AS pct_revenue,
       ROUND(100.0 * SUM(SUM(revenue)) OVER (ORDER BY decile)
             / SUM(SUM(revenue)) OVER (), 1)                     AS cumulative_pct_revenue
FROM ranked
GROUP BY decile
ORDER BY decile;

-- name: seller_scorecard
-- Sellers with 100+ delivered orders
WITH seller_orders AS (
    SELECT DISTINCT i.seller_id, o.order_id, o.is_late, o.review_score,
           o.delivery_days
    FROM order_items i
    JOIN v_orders o ON o.order_id = i.order_id
    WHERE o.is_delivered = 1
),
seller_rev AS (
    SELECT i.seller_id, SUM(i.price) AS revenue
    FROM order_items i
    JOIN v_orders o ON o.order_id = i.order_id
    GROUP BY i.seller_id
)
SELECT so.seller_id,
       s.seller_state,
       COUNT(*)                          AS delivered_orders,
       ROUND(r.revenue, 0)               AS revenue,
       ROUND(AVG(so.delivery_days), 1)   AS avg_delivery_days,
       ROUND(100.0 * AVG(so.is_late), 1) AS late_pct,
       ROUND(AVG(so.review_score), 2)    AS avg_review_score
FROM seller_orders so
JOIN sellers s     ON s.seller_id = so.seller_id
JOIN seller_rev r  ON r.seller_id = so.seller_id
GROUP BY so.seller_id
HAVING COUNT(*) >= 100
ORDER BY late_pct DESC;

-- name: late_orders_concentration
-- Share of all late deliveries caused by the worst 10% of active sellers
WITH seller_orders AS (
    SELECT DISTINCT i.seller_id, o.order_id, o.is_late
    FROM order_items i
    JOIN v_orders o ON o.order_id = i.order_id
    WHERE o.is_delivered = 1
),
per_seller AS (
    SELECT seller_id, COUNT(*) AS orders, SUM(is_late) AS late_orders
    FROM seller_orders
    GROUP BY seller_id
    HAVING COUNT(*) >= 20
),
ranked AS (
    SELECT *, NTILE(10) OVER (ORDER BY 1.0 * late_orders / orders DESC) AS decile
    FROM per_seller
)
SELECT decile                                                       AS late_rate_decile,
       COUNT(*)                                                     AS sellers,
       SUM(orders)                                                  AS orders,
       SUM(late_orders)                                             AS late_orders,
       ROUND(100.0 * SUM(late_orders) / SUM(orders), 1)             AS late_pct,
       ROUND(100.0 * SUM(late_orders) / SUM(SUM(late_orders)) OVER (), 1) AS pct_of_all_late
FROM ranked
GROUP BY decile
ORDER BY decile;
