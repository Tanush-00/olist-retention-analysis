"""
Step 0 - Download the Olist dataset from Kaggle into data/raw/.

    python scripts/download_data.py

Skipped automatically when all 9 CSV files are already present.
If the download fails, get the zip manually from
https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce and unzip it into data/raw/.
"""
import io
import sys
import urllib.request
import zipfile

from config import RAW_DIR

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

URL = "https://www.kaggle.com/api/v1/datasets/download/olistbr/brazilian-ecommerce"
EXPECTED_FILES = [
    "olist_customers_dataset.csv",
    "olist_geolocation_dataset.csv",
    "olist_order_items_dataset.csv",
    "olist_order_payments_dataset.csv",
    "olist_order_reviews_dataset.csv",
    "olist_orders_dataset.csv",
    "olist_products_dataset.csv",
    "olist_sellers_dataset.csv",
    "product_category_name_translation.csv",
]


def main() -> None:
    if all((RAW_DIR / name).exists() for name in EXPECTED_FILES):
        print("Raw data already present - skipping download.")
        return

    RAW_DIR.mkdir(parents=True, exist_ok=True)
    print(f"Downloading {URL} (about 43 MB) ...")
    request = urllib.request.Request(URL, headers={"User-Agent": "olist-analysis-project"})
    try:
        with urllib.request.urlopen(request, timeout=300) as response:
            payload = response.read()
        archive = zipfile.ZipFile(io.BytesIO(payload))
    except Exception as exc:  # network error, HTTP error, not a zip ...
        sys.exit(f"Download failed: {exc}\n"
                 "Download the zip manually from https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce\n"
                 f"and unzip it into {RAW_DIR}")

    with archive:
        # Extract only the expected files, by name (never trust paths inside a zip)
        for name in EXPECTED_FILES:
            (RAW_DIR / name).write_bytes(archive.read(name))
    print(f"Saved {len(EXPECTED_FILES)} files to {RAW_DIR}")


if __name__ == "__main__":
    main()
