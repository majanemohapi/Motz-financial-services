"""Rebuild descriptive audit artifacts from the supplied Kaggle train.csv.
Run from project root: python scripts/dataset_audit.py
Requires pandas, matplotlib, numpy.
"""
from pathlib import Path
import json
import pandas as pd
import matplotlib.pyplot as plt

ROOT = Path(__file__).resolve().parents[1]
CSV = ROOT / "data" / "train.csv"
OUT = ROOT / "outputs"
OUT.mkdir(exist_ok=True)
df = pd.read_csv(CSV)
if len(df.columns) != 13 or "Loan_Status" not in df.columns:
    raise ValueError("Unexpected dataset schema; check that this is the supplied Kaggle train.csv.")
missing = df.isna().sum().sort_values(ascending=False)
audit = {
    "dataset_file": "data/train.csv",
    "rows": int(df.shape[0]),
    "columns": int(df.shape[1]),
    "target_counts": {str(k): int(v) for k, v in df["Loan_Status"].value_counts().items()},
    "missing_by_column": {str(k): int(v) for k, v in df.isna().sum().items()},
    "exact_duplicate_rows": int(df.duplicated().sum()),
    "duplicate_loan_ids": int(df["Loan_ID"].duplicated().sum()),
    "numeric_summary": df.select_dtypes(include="number").describe().round(3).to_dict(),
}
(OUT / "dataset_audit.json").write_text(json.dumps(audit, indent=2), encoding="utf-8")
df["Loan_Status"].value_counts().reindex(["Y", "N"]).plot(kind="bar")
plt.title("Loan Outcome Distribution (Kaggle Training Data)")
plt.xlabel("Loan status (Y=approved, N=rejected)")
plt.ylabel("Applications")
plt.tight_layout()
plt.savefig(OUT / "01_loan_status_distribution.png", dpi=160)
plt.close()
df["ApplicantIncome"].plot(kind="hist", bins=30)
plt.title("Applicant Income Distribution")
plt.xlabel("Applicant income")
plt.ylabel("Applications")
plt.tight_layout()
plt.savefig(OUT / "02_applicant_income_distribution.png", dpi=160)
plt.close()
missing[missing > 0].sort_values().plot(kind="barh")
plt.title("Missing Values by Field")
plt.xlabel("Missing cells")
plt.ylabel("Dataset field")
plt.tight_layout()
plt.savefig(OUT / "03_missing_values.png", dpi=160)
plt.close()
pd.crosstab(df["Property_Area"], df["Loan_Status"]).reindex(["Urban", "Semiurban", "Rural"]).plot(kind="bar")
plt.title("Loan Outcomes by Property Area")
plt.xlabel("Property area")
plt.ylabel("Applications")
plt.xticks(rotation=0)
plt.tight_layout()
plt.savefig(OUT / "04_outcomes_by_property_area.png", dpi=160)
plt.close()
print(f"Audit complete: {len(df)} rows, {len(df.columns)} columns; outputs written to {OUT}")
