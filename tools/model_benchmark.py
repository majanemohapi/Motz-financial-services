"""Leakage-safe benchmark for Motz loan classification.

This is an evaluation utility only. It does not change the Prolog production
predictor or make lending decisions. Uses 5-fold stratified out-of-fold
predictions so every reported prediction is made by a model that did not train
on that row.
"""
from pathlib import Path
import json
import warnings

import numpy as np
import pandas as pd
from sklearn.compose import ColumnTransformer
from sklearn.ensemble import ExtraTreesClassifier, RandomForestClassifier
from sklearn.impute import SimpleImputer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import (
    accuracy_score, balanced_accuracy_score, confusion_matrix,
    f1_score, precision_score, recall_score,
)
from sklearn.model_selection import StratifiedKFold, cross_val_predict
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder, StandardScaler
from sklearn.svm import SVC

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data" / "train.csv"
TARGET = "Loan_Status"
RANDOM_STATE = 20261116
FOLDS = 5


def evaluate(y_true, y_pred):
    tn, fp, fn, tp = confusion_matrix(y_true, y_pred, labels=["N", "Y"]).ravel()
    specificity = tn / (tn + fp) if (tn + fp) else 0.0
    return {
        "accuracy": round(accuracy_score(y_true, y_pred) * 100, 2),
        "balanced_accuracy": round(balanced_accuracy_score(y_true, y_pred) * 100, 2),
        "precision_approved": round(precision_score(y_true, y_pred, pos_label="Y", zero_division=0) * 100, 2),
        "recall_approved": round(recall_score(y_true, y_pred, pos_label="Y", zero_division=0) * 100, 2),
        "specificity_rejected": round(specificity * 100, 2),
        "f1_approved": round(f1_score(y_true, y_pred, pos_label="Y", zero_division=0) * 100, 2),
        "incorrect_approvals_fp": int(fp),
        "incorrect_rejections_fn": int(fn),
        "true_approvals_tp": int(tp),
        "true_rejections_tn": int(tn),
    }


def build_pipeline(model, numeric, categorical):
    preprocess = ColumnTransformer([
        ("numeric", Pipeline([
            ("imputer", SimpleImputer(strategy="median")),
            ("scale", StandardScaler()),
        ]), numeric),
        ("categorical", Pipeline([
            ("imputer", SimpleImputer(strategy="most_frequent")),
            ("onehot", OneHotEncoder(handle_unknown="ignore")),
        ]), categorical),
    ])
    return Pipeline([("preprocess", preprocess), ("model", model)])


def main():
    if not DATA.exists():
        raise FileNotFoundError(f"Dataset not found: {DATA}")

    df = pd.read_csv(DATA)
    if TARGET not in df.columns:
        raise ValueError(f"Missing target column: {TARGET}")
    df = df.dropna(subset=[TARGET]).copy()
    df[TARGET] = df[TARGET].astype(str).str.strip().str.upper()
    df = df[df[TARGET].isin(["Y", "N"])]

    excluded = [TARGET, "Loan_ID"]
    # Keep a second, fairness-aware comparison that omits sex and marital status.
    feature_sets = {
        "all_recorded_features": [c for c in df.columns if c not in excluded],
        "without_gender_marital": [
            c for c in df.columns if c not in excluded and c not in {"Gender", "Married"}
        ],
    }

    models = {
        "logistic_regression": LogisticRegression(max_iter=3000, random_state=RANDOM_STATE),
        "random_forest": RandomForestClassifier(
            n_estimators=500, min_samples_leaf=2, class_weight="balanced",
            random_state=RANDOM_STATE, n_jobs=-1
        ),
        "extra_trees": ExtraTreesClassifier(
            n_estimators=500, min_samples_leaf=2, class_weight="balanced",
            random_state=RANDOM_STATE, n_jobs=-1
        ),
        "rbf_svc": SVC(C=1.0, kernel="rbf", class_weight="balanced"),
    }

    cv = StratifiedKFold(n_splits=FOLDS, shuffle=True, random_state=RANDOM_STATE)
    results = []
    for feature_set, columns in feature_sets.items():
        numeric = [c for c in columns if pd.api.types.is_numeric_dtype(df[c])]
        categorical = [c for c in columns if c not in numeric]
        X, y = df[columns], df[TARGET]

        for model_name, model in models.items():
            pipeline = build_pipeline(model, numeric, categorical)
            with warnings.catch_warnings():
                warnings.simplefilter("ignore")
                predictions = cross_val_predict(
                    pipeline, X, y, cv=cv, method="predict", n_jobs=1
                )
            results.append({
                "feature_set": feature_set,
                "model": model_name,
                **evaluate(y, predictions),
            })

    results.sort(
        key=lambda row: (
            row["balanced_accuracy"],
            row["specificity_rejected"],
            row["accuracy"],
        ),
        reverse=True,
    )
    report = {
        "dataset_rows": int(len(df)),
        "folds": FOLDS,
        "positive_class": "Y (historical approval label)",
        "selection_priority": "balanced accuracy, then rejection specificity, then accuracy",
        "warning": (
            "Historical Kaggle decisions are not actual repayment outcomes. "
            "Cross-validation scores are research estimates, not calibrated "
            "probabilities or evidence of real-world lending suitability."
        ),
        "results": results,
    }
    output = ROOT / "benchmark-results.json"
    output.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report, indent=2))
    print(f"Saved: {output}")


if __name__ == "__main__":
    main()
