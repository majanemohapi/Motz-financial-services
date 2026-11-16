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


def threshold_metrics(y_true, approval_scores, threshold):
    predicted = np.where(approval_scores >= threshold, "Y", "N")
    return evaluate(y_true, predicted)


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



from sklearn.base import BaseEstimator, ClassifierMixin

class PrologStyleNaiveBayes(BaseEstimator, ClassifierMixin):
    """Python test replica of the categorical Naive Bayes rules in main.pl."""
    DOMAINS = [3, 3, 5, 3, 3, 5, 5, 5, 4, 3, 4, 5]
    COLUMNS = [
        "Gender", "Married", "Dependents", "Education", "Self_Employed",
        "ApplicantIncome", "CoapplicantIncome", "LoanAmount",
        "Loan_Amount_Term", "Credit_History", "Property_Area",
    ]

    @staticmethod
    def _category(value):
        if pd.isna(value) or str(value).strip().lower() in {"", "na", "null", "n/a", "?"}:
            return "missing"
        value = str(value).strip().lower()
        return "not graduate" if value == "not_graduate" else value

    @staticmethod
    def _number(value):
        try:
            number = float(value)
            return number if np.isfinite(number) else None
        except (TypeError, ValueError):
            return None

    @classmethod
    def _features(cls, row):
        gender = cls._category(row["Gender"])
        married = cls._category(row["Married"])
        dependents = cls._category(row["Dependents"])
        if dependents in {"3", "3+"}:
            dependents = "dep_3_plus"
        education = cls._category(row["Education"])
        self_employed = cls._category(row["Self_Employed"])
        applicant = cls._number(row["ApplicantIncome"])
        coapplicant = cls._number(row["CoapplicantIncome"])
        loan_amount = cls._number(row["LoanAmount"])
        term = cls._number(row["Loan_Amount_Term"])
        credit = cls._number(row["Credit_History"])
        property_area = cls._category(row["Property_Area"])

        def income_band(v):
            if v is None: return "missing"
            if v < 2500: return "low"
            if v < 6000: return "medium"
            if v < 12000: return "high"
            return "very_high"

        def co_income_band(v):
            if v is None: return "missing"
            if v == 0: return "none"
            if v < 2000: return "low"
            if v < 5000: return "medium"
            return "high"

        def amount_band(v):
            if v is None: return "missing"
            if v < 100: return "low"
            if v < 200: return "medium"
            if v < 350: return "high"
            return "very_high"

        def term_band(v):
            if v is None: return "missing"
            if v < 180: return "short"
            if v <= 360: return "standard"
            return "long"

        if credit not in (0, 1):
            credit = "missing"
        total_income = (applicant or 0) + (coapplicant or 0)
        if applicant is None or coapplicant is None or loan_amount is None or term is None or term <= 0 or total_income <= 0:
            burden = "missing"
        else:
            ratio = (loan_amount * 1000 / term) / total_income
            burden = "low" if ratio <= .15 else "moderate" if ratio <= .30 else "high" if ratio <= .50 else "very_high"

        return [
            gender, married, dependents, education, self_employed,
            income_band(applicant), co_income_band(coapplicant),
            amount_band(loan_amount), term_band(term), credit,
            property_area, burden,
        ]

    def fit(self, X, y):
        self.classes_ = np.array(["N", "Y"])
        self.rows_ = [self._features(row) for _, row in X.iterrows()]
        self.labels_ = np.asarray(y)
        self.class_rows_ = {
            label: [row for row, actual in zip(self.rows_, self.labels_) if actual == label]
            for label in self.classes_
        }
        return self

    def predict_proba(self, X):
        output = []
        for _, raw in X.iterrows():
            features = self._features(raw)
            scores = []
            total = len(self.labels_)
            for label in self.classes_:
                rows = self.class_rows_[label]
                class_count = len(rows)
                score = np.log(class_count / total)
                for position, value in enumerate(features):
                    count = sum(row[position] == value for row in rows)
                    score += np.log((count + 1) / (class_count + self.DOMAINS[position]))
                scores.append(score)
            scores = np.asarray(scores)
            probabilities = np.exp(scores - scores.max())
            probabilities /= probabilities.sum()
            output.append(probabilities)
        return np.asarray(output)

    def predict(self, X):
        return self.classes_[np.argmax(self.predict_proba(X), axis=1)]


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
        "prolog_naive_bayes_replica": None,
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
    threshold_results = []
    for feature_set, columns in feature_sets.items():
        numeric = [c for c in columns if pd.api.types.is_numeric_dtype(df[c])]
        categorical = [c for c in columns if c not in numeric]
        X, y = df[columns], df[TARGET]

        for model_name, model in models.items():
            if model_name == "prolog_naive_bayes_replica" and feature_set != "all_recorded_features":
                continue
            pipeline = (
                PrologStyleNaiveBayes()
                if model_name == "prolog_naive_bayes_replica"
                else build_pipeline(model, numeric, categorical)
            )
            with warnings.catch_warnings():
                warnings.simplefilter("ignore")
                predictions = cross_val_predict(
                    pipeline, X, y, cv=cv, method="predict", n_jobs=1
                )
                # Out-of-fold probabilities support a diagnostic threshold sweep.
                # This sweep is exploratory, not an independent test.
                approval_scores = (
                    cross_val_predict(
                        pipeline, X, y, cv=cv, method="predict_proba", n_jobs=1
                    )[:, 1]
                    if model_name in {"prolog_naive_bayes_replica", "logistic_regression"}
                    else None
                )

            results.append({
                "feature_set": feature_set,
                "model": model_name,
                **evaluate(y, predictions),
            })

            if model_name in {"prolog_naive_bayes_replica", "logistic_regression"}:
                for threshold in np.arange(0.30, 0.701, 0.025):
                    threshold_results.append({
                        "feature_set": feature_set,
                        "model": model_name,
                        "approval_threshold": round(float(threshold), 3),
                        **threshold_metrics(y, approval_scores, threshold),
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
        "threshold_analysis": {
            "description": (
                "Exploratory out-of-fold threshold sweep for Prolog-style Naive Bayes "
                "and logistic regression. The same cross-validation predictions are "
                "used to inspect thresholds, so this is diagnostic only; do not deploy "
                "a selected threshold without a separate untouched test."
            ),
            "results": threshold_results,
        },
    }
    output = ROOT / "benchmark-results.json"
    output.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report, indent=2))
    print(f"Saved: {output}")


if __name__ == "__main__":
    main()
