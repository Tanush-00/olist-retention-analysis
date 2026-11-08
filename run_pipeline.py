"""
Run the whole project end to end:

    python run_pipeline.py                  # everything
    python run_pipeline.py --skip-notebook  # skip re-executing the notebook

Steps: download data -> load SQLite -> run SQL -> export Power BI tables
       -> build HTML dashboard -> execute the analysis notebook.
"""
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent
PY = sys.executable

STEPS = [
    ("Download dataset", [PY, "scripts/download_data.py"]),
    ("Load CSVs into SQLite", [PY, "scripts/load_data.py"]),
    ("Run SQL analysis", [PY, "scripts/run_sql.py"]),
    ("Export Power BI tables", [PY, "scripts/export_powerbi.py"]),
    ("Build HTML dashboard", [PY, "scripts/build_dashboard.py"]),
    ("Execute analysis notebook", [PY, "-m", "nbconvert", "--to", "notebook", "--execute", "--inplace",
                                   "--ExecutePreprocessor.timeout=900", "notebooks/olist_analysis.ipynb"]),
]


def main() -> None:
    skip_notebook = "--skip-notebook" in sys.argv
    start = time.time()
    for i, (name, cmd) in enumerate(STEPS, 1):
        if skip_notebook and "nbconvert" in cmd:
            print(f"\n[{i}/{len(STEPS)}] {name}: skipped")
            continue
        print(f"\n[{i}/{len(STEPS)}] {name}\n{'-' * 60}", flush=True)
        step_start = time.time()
        result = subprocess.run(cmd, cwd=ROOT)
        if result.returncode != 0:
            sys.exit(f"\nStep failed: {name} (exit code {result.returncode})")
        print(f"[{name}] done in {time.time() - step_start:.0f}s", flush=True)
    print(f"\nPipeline finished in {time.time() - start:.0f}s.")
    print("Open dashboard/olist_dashboard.html in a browser, or notebooks/olist_analysis.ipynb in Jupyter.")


if __name__ == "__main__":
    main()
