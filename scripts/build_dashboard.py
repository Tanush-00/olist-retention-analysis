"""
Step 4 - Build the interactive HTML dashboard.

    python scripts/build_dashboard.py

Reads every SQL result in outputs/sql_results/, embeds it as JSON into
dashboard/dashboard_template.html and writes dashboard/olist_dashboard.html.
Open that file in any browser (charts load Chart.js from a CDN).
"""
import json
import math
import sys
from datetime import date

import pandas as pd

from config import DASHBOARD_DIR, SQL_RESULTS_DIR

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

TEMPLATE = DASHBOARD_DIR / "dashboard_template.html"
OUTPUT = DASHBOARD_DIR / "olist_dashboard.html"
PLACEHOLDER = "__DATA_JSON__"


def clean(value):
    if isinstance(value, float) and math.isnan(value):
        return None
    return value


def main() -> None:
    files = sorted(SQL_RESULTS_DIR.glob("*.csv"))
    if not files:
        sys.exit("No SQL results found. Run scripts/run_sql.py first.")

    data = {}
    for path in files:
        key = path.stem.split("__", 1)[1]           # "04_business_kpis__monthly_trend" -> "monthly_trend"
        if key in data:
            sys.exit(f"Duplicate result name: {key}")
        df = pd.read_csv(path, dtype={"purchase_days": str})
        data[key] = [{k: clean(v) for k, v in row.items()} for row in df.to_dict(orient="records")]
    data["_generated"] = date.today().isoformat()

    html = TEMPLATE.read_text(encoding="utf-8")
    if PLACEHOLDER not in html:
        sys.exit(f"{PLACEHOLDER} not found in {TEMPLATE.name}")
    payload = json.dumps(data, ensure_ascii=False, separators=(",", ":")).replace("</", "<\\/")
    OUTPUT.write_text(html.replace(PLACEHOLDER, payload), encoding="utf-8")
    print(f"Dashboard written to {OUTPUT} ({OUTPUT.stat().st_size / 1024:.0f} KB, {len(files)} result sets)")


if __name__ == "__main__":
    main()
