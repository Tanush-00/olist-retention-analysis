"""Shared project paths and analysis settings."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

RAW_DIR = ROOT / "data" / "raw"
PROCESSED_DIR = ROOT / "data" / "processed"
DB_PATH = ROOT / "database" / "olist.db"
SQL_DIR = ROOT / "sql"
SQL_RESULTS_DIR = ROOT / "outputs" / "sql_results"
ROBUSTNESS_DIR = ROOT / "outputs" / "robustness"
FIGURES_DIR = ROOT / "outputs" / "figures"
DASHBOARD_DIR = ROOT / "dashboard"

# The dataset starts in Sep-2016 and ends in Oct-2018, but the first and last
# months are very thin (a handful of orders). Monthly trends use full months only.
TREND_START = "2017-01"
TREND_END = "2018-08"
