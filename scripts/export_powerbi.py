"""
Step 3 - Export a clean star schema for Power BI into data/processed/.

    python scripts/export_powerbi.py

Tables
  fact_orders        one row per valid order (value, delivery, review metrics)
  fact_order_items   one row per item sold (for category / seller analysis)
  dim_customers      one row per real customer, with RFM scores and segment
  dim_products       product -> English category
  dim_sellers        seller location
  dim_date           calendar table (mark as date table in Power BI)
  cohort_retention   cohort_month x month_number retention (for the heatmap matrix)

See dashboard/powerbi_guide.md for the model, DAX measures and page layout.
"""
import sqlite3
import sys

import pandas as pd

from config import DB_PATH, PROCESSED_DIR, SQL_RESULTS_DIR

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

QUERIES = {
    "fact_orders": """
        SELECT order_id, customer_unique_id, customer_state, order_status,
               purchase_date, purchase_month, delivered_date, estimated_date,
               n_items, n_sellers, product_value, freight_value, order_value,
               payment_type, payment_installments, review_score,
               is_delivered, delivery_days, delay_days, is_late,
               CASE WHEN is_delivered = 0 OR delay_days IS NULL THEN NULL
                    WHEN delay_days <= -8 THEN '1. 8+ days early'
                    WHEN delay_days <= -1 THEN '2. 1-7 days early'
                    WHEN delay_days = 0   THEN '3. On estimated day'
                    WHEN delay_days <= 3  THEN '4. 1-3 days late'
                    WHEN delay_days <= 7  THEN '5. 4-7 days late'
                    WHEN delay_days <= 14 THEN '6. 8-14 days late'
                    ELSE '7. 15+ days late' END AS delay_bucket
        FROM v_orders
    """,
    "fact_order_items": """
        SELECT i.order_id, i.order_item_id, i.product_id, i.seller_id,
               o.purchase_date, o.customer_state, o.is_late, o.review_score,
               i.price, i.freight_value
        FROM order_items i
        JOIN v_orders o ON o.order_id = i.order_id
    """,
    "dim_customers": """
        SELECT c.customer_unique_id, c.customer_state, c.n_orders, c.n_purchase_days,
               c.total_spend, DATE(c.first_purchase_ts) AS first_purchase_date,
               DATE(c.last_purchase_ts) AS last_purchase_date, c.cohort_month,
               CASE WHEN c.n_purchase_days >= 2 THEN 1 ELSE 0 END AS is_repeat_customer,
               r.recency_days, r.r_score, r.f_score, r.m_score, r.segment
        FROM v_customers c
        LEFT JOIN rfm_customers r ON r.customer_unique_id = c.customer_unique_id
    """,
    "dim_products": """
        SELECT p.product_id,
               COALESCE(t.product_category_name_english, p.product_category_name, 'unknown') AS category,
               p.product_weight_g, p.product_photos_qty
        FROM products p
        LEFT JOIN category_translation t ON t.product_category_name = p.product_category_name
    """,
    "dim_sellers": "SELECT seller_id, seller_city, seller_state FROM sellers",
}


def build_dim_date(start: str, end: str) -> pd.DataFrame:
    dates = pd.date_range(start, end, freq="D")
    return pd.DataFrame({
        "date": dates.strftime("%Y-%m-%d"),
        "year": dates.year,
        "quarter": "Q" + dates.quarter.astype(str),
        "month_number": dates.month,
        "month_name": dates.strftime("%b"),
        "year_month": dates.strftime("%Y-%m"),
        "weekday_number": dates.dayofweek + 1,      # 1 = Monday
        "weekday_name": dates.strftime("%a"),
    })


def main() -> None:
    if not DB_PATH.exists():
        sys.exit("Database not found. Run scripts/load_data.py and scripts/run_sql.py first.")
    PROCESSED_DIR.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    try:
        for name, sql in QUERIES.items():
            df = pd.read_sql_query(sql, conn)
            df.to_csv(PROCESSED_DIR / f"{name}.csv", index=False)
            print(f"  {name:<18}{len(df):>9,} rows")
    finally:
        conn.close()

    dim_date = build_dim_date("2016-09-01", "2018-10-31")
    dim_date.to_csv(PROCESSED_DIR / "dim_date.csv", index=False)
    print(f"  {'dim_date':<18}{len(dim_date):>9,} rows")

    cohort = pd.read_csv(SQL_RESULTS_DIR / "05_customer_retention__cohort_retention.csv")
    cohort.to_csv(PROCESSED_DIR / "cohort_retention.csv", index=False)
    print(f"  {'cohort_retention':<18}{len(cohort):>9,} rows")


if __name__ == "__main__":
    main()
