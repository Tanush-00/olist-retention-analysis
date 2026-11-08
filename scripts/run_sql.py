"""
Step 2 - Run every analysis SQL file (02_*.sql ... 08_*.sql) against the DB.

    python scripts/run_sql.py            # run all files
    python scripts/run_sql.py 07         # run only files starting with 07

Each SQL file is split into blocks that start with a line like
    -- name: monthly_trend
SELECT / WITH blocks are executed and saved to
    outputs/sql_results/<file>__<name>.csv
Other blocks (CREATE VIEW, CREATE TABLE ...) are simply executed.
"""
import re
import sqlite3
import sys

import pandas as pd

from config import DB_PATH, SQL_DIR, SQL_RESULTS_DIR

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
pd.set_option("display.width", 200)
pd.set_option("display.max_columns", 20)

BLOCK_MARKER = re.compile(r"^--\s*name:\s*(\w+)\s*$", re.MULTILINE)


def split_blocks(sql_text: str) -> list[tuple[str, str]]:
    parts = BLOCK_MARKER.split(sql_text)
    return [(parts[i], parts[i + 1].strip()) for i in range(1, len(parts), 2)]


def is_query(sql: str) -> bool:
    code = "\n".join(line for line in sql.splitlines()
                     if not line.strip().startswith("--")).strip().upper()
    return code.startswith(("SELECT", "WITH"))


def run_file(conn: sqlite3.Connection, path, preview_rows: int = 8) -> None:
    print(f"\n{'=' * 78}\n{path.name}\n{'=' * 78}")
    for name, sql in split_blocks(path.read_text(encoding="utf-8")):
        if is_query(sql):
            df = pd.read_sql_query(sql, conn)
            df.to_csv(SQL_RESULTS_DIR / f"{path.stem}__{name}.csv", index=False)
            print(f"\n-- {name}  ({len(df)} rows)")
            print(df.head(preview_rows).to_string(index=False))
        else:
            conn.executescript(sql)
            print(f"-- {name}: done")


def main() -> None:
    if not DB_PATH.exists():
        sys.exit("Database not found. Run scripts/load_data.py first.")
    prefix = sys.argv[1] if len(sys.argv) > 1 else ""
    SQL_RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    try:
        for path in sorted(SQL_DIR.glob("0*.sql")):
            if path.name.startswith("01_"):
                continue  # schema is applied by load_data.py
            if prefix and not path.name.startswith(prefix):
                continue
            run_file(conn, path)
        conn.commit()
    finally:
        conn.close()


if __name__ == "__main__":
    main()
