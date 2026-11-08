-- =====================================================================
-- 05_customer_retention.sql
-- How many customers come back, how fast, and how retention decays
-- month by month (cohort analysis).
-- =====================================================================

-- name: purchase_frequency
SELECT CASE WHEN n_purchase_days >= 4 THEN '4+'
            ELSE CAST(n_purchase_days AS TEXT) END          AS purchase_days,
       COUNT(*)                                             AS customers,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)   AS pct_of_customers,
       ROUND(SUM(total_spend), 0)                           AS revenue,
       ROUND(100.0 * SUM(total_spend) / SUM(SUM(total_spend)) OVER (), 2) AS pct_of_revenue
FROM v_customers
GROUP BY 1
ORDER BY 1;

-- name: repeat_rate
SELECT COUNT(*)                                             AS customers,
       SUM(n_orders >= 2)                                   AS customers_with_2plus_orders,
       SUM(n_purchase_days >= 2)                            AS repeat_customers,
       ROUND(100.0 * SUM(n_purchase_days >= 2) / COUNT(*), 2) AS repeat_rate_pct,
       ROUND(AVG(CASE WHEN n_purchase_days >= 2 THEN total_spend END), 2) AS avg_spend_repeat,
       ROUND(AVG(CASE WHEN n_purchase_days = 1 THEN total_spend END), 2)  AS avg_spend_one_time
FROM v_customers;

-- name: days_to_second_purchase
WITH purchase_days AS (
    SELECT DISTINCT customer_unique_id, purchase_date FROM v_orders
),
ranked AS (
    SELECT customer_unique_id,
           purchase_date,
           ROW_NUMBER() OVER (PARTITION BY customer_unique_id ORDER BY purchase_date) AS nth
    FROM purchase_days
),
gaps AS (
    SELECT julianday(b.purchase_date) - julianday(a.purchase_date) AS days_gap
    FROM ranked a
    JOIN ranked b ON b.customer_unique_id = a.customer_unique_id AND b.nth = 2
    WHERE a.nth = 1
)
SELECT CASE WHEN days_gap <= 30  THEN '1. within 30 days'
            WHEN days_gap <= 90  THEN '2. 31-90 days'
            WHEN days_gap <= 180 THEN '3. 91-180 days'
            WHEN days_gap <= 365 THEN '4. 181-365 days'
            ELSE '5. over 1 year' END                     AS time_to_2nd_purchase,
       COUNT(*)                                           AS customers,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_repeaters
FROM gaps
GROUP BY 1
ORDER BY 1;

-- name: cohort_retention
-- Long format: cohort_month x month_number -> % of the cohort active again.
-- month_number 0 = first purchase month (always 100%).
WITH first_month AS (
    SELECT customer_unique_id, cohort_month FROM v_customers
),
activity AS (
    SELECT DISTINCT
           o.customer_unique_id,
           f.cohort_month,
           (CAST(substr(o.purchase_month, 1, 4) AS INTEGER) * 12
              + CAST(substr(o.purchase_month, 6, 2) AS INTEGER))
         - (CAST(substr(f.cohort_month, 1, 4) AS INTEGER) * 12
              + CAST(substr(f.cohort_month, 6, 2) AS INTEGER))  AS month_number
    FROM v_orders o
    JOIN first_month f ON f.customer_unique_id = o.customer_unique_id
),
cohort_size AS (
    SELECT cohort_month, COUNT(*) AS cohort_customers
    FROM first_month
    GROUP BY cohort_month
)
SELECT a.cohort_month,
       s.cohort_customers,
       a.month_number,
       COUNT(*)                                       AS active_customers,
       ROUND(100.0 * COUNT(*) / s.cohort_customers, 2) AS retention_pct
FROM activity a
JOIN cohort_size s ON s.cohort_month = a.cohort_month
WHERE a.cohort_month BETWEEN '2017-01' AND '2018-08'
  AND a.month_number <= 12
GROUP BY a.cohort_month, a.month_number
ORDER BY a.cohort_month, a.month_number;

-- name: retention_curve
-- Average retention by month since first purchase, weighted by cohort size.
-- Only cohorts old enough to be observed for that many months are counted.
WITH cohorts AS (
    SELECT cohort_month,
           COUNT(*) AS cohort_customers,
           (2018 * 12 + 8)
         - (CAST(substr(cohort_month, 1, 4) AS INTEGER) * 12
              + CAST(substr(cohort_month, 6, 2) AS INTEGER)) AS months_observable
    FROM v_customers
    WHERE cohort_month BETWEEN '2017-01' AND '2018-08'
    GROUP BY cohort_month
),
activity AS (
    SELECT DISTINCT
           o.customer_unique_id,
           c.cohort_month,
           (CAST(substr(o.purchase_month, 1, 4) AS INTEGER) * 12
              + CAST(substr(o.purchase_month, 6, 2) AS INTEGER))
         - (CAST(substr(c.cohort_month, 1, 4) AS INTEGER) * 12
              + CAST(substr(c.cohort_month, 6, 2) AS INTEGER)) AS month_number
    FROM v_orders o
    JOIN v_customers c ON c.customer_unique_id = o.customer_unique_id
),
months AS (
    SELECT DISTINCT month_number FROM activity WHERE month_number BETWEEN 1 AND 12
)
SELECT m.month_number,
       SUM(co.cohort_customers)                                   AS customers_observed,
       (SELECT COUNT(*) FROM activity a
         JOIN cohorts c2 ON c2.cohort_month = a.cohort_month
         WHERE a.month_number = m.month_number
           AND c2.months_observable >= m.month_number)            AS active_customers,
       ROUND(100.0 * (SELECT COUNT(*) FROM activity a
         JOIN cohorts c2 ON c2.cohort_month = a.cohort_month
         WHERE a.month_number = m.month_number
           AND c2.months_observable >= m.month_number)
         / SUM(co.cohort_customers), 3)                           AS retention_pct
FROM months m
JOIN cohorts co ON co.months_observable >= m.month_number
GROUP BY m.month_number
ORDER BY m.month_number;
