"""
Step 1 - Load the raw Olist CSVs into a SQLite database.

    python scripts/load_data.py

Creates database/olist.db using the schema in sql/01_schema.sql.
"""
import sqlite3
import sys
import time

import pandas as pd

from config import DB_PATH, RAW_DIR, SQL_DIR

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

# table name -> source file (loaded in this order)
TABLES = {
    "customers": "olist_customers_dataset.csv",
    "sellers": "olist_sellers_dataset.csv",
    "category_translation": "product_category_name_translation.csv",
    "products": "olist_products_dataset.csv",
    "orders": "olist_orders_dataset.csv",
    "order_items": "olist_order_items_dataset.csv",
    "order_payments": "olist_order_payments_dataset.csv",
    "order_reviews": "olist_order_reviews_dataset.csv",
    "geolocation": "olist_geolocation_dataset.csv",
}

# Zip prefixes must stay text, otherwise leading zeros are lost ("01037" -> 1037)
TEXT_COLUMNS = {
    "customer_zip_code_prefix": str,
    "seller_zip_code_prefix": str,
    "geolocation_zip_code_prefix": str,
}


def main() -> None:
    missing = [f for f in TABLES.values() if not (RAW_DIR / f).exists()]
    if missing:
        sys.exit(f"Missing raw files in {RAW_DIR}: {missing}\n"
                 "Download the dataset first (see README -> How to run).")

    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    if DB_PATH.exists():
        DB_PATH.unlink()

    start = time.time()
    conn = sqlite3.connect(DB_PATH)
    try:
        conn.executescript((SQL_DIR / "01_schema.sql").read_text(encoding="utf-8"))
        print(f"Loading raw CSVs into {DB_PATH.name}\n")
        for table, file_name in TABLES.items():
            df = pd.read_csv(RAW_DIR / file_name, dtype=TEXT_COLUMNS, encoding="utf-8-sig")
            df.to_sql(table, conn, if_exists="append", index=False, chunksize=20_000)
            print(f"  {table:<22}{len(df):>12,} rows")
        conn.commit()
    finally:
        conn.close()
    print(f"\nDone in {time.time() - start:.1f}s")


if __name__ == "__main__":
    main()
