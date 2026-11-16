# Motz Financial Services — Model Benchmark Report

**Dataset:** Kaggle loan training data (`data/train.csv`)  
**Rows evaluated:** 614  
**Evaluation:** 5-fold stratified cross-validation with out-of-fold predictions  
**Target:** Historical `Loan_Status` (`Y` = approved, `N` = rejected)

## Results

Scores are percentages. Error counts below are summed across all 614 out-of-fold predictions, not the 124-row holdout used by the live Prolog performance endpoint.

| Candidate | Feature set | Accuracy | Balanced accuracy | Rejection specificity | Incorrect approvals (FP) | Incorrect rejections (FN) |
|---|---|---:|---:|---:|---:|---:|
| Logistic regression | Without gender/marital | 80.94% | 70.81% | 43.75% | 108 | 9 |
| Logistic regression | All recorded features | 80.78% | 70.69% | 43.75% | 108 | 10 |
| Random forest | All recorded features | 76.06% | 69.81% | 53.12% | 90 | 57 |
| Prolog Naive Bayes replica | All recorded features | 79.15% | 69.79% | 44.79% | 106 | 22 |
| Random forest | Without gender/marital | 76.06% | 69.67% | 52.60% | 91 | 56 |
| RBF SVC | All recorded features | 77.52% | 69.03% | 46.35% | 103 | 35 |
| Extra trees | Without gender/marital | 75.90% | 69.12% | 51.04% | 94 | 54 |
| RBF SVC | Without gender/marital | 76.55% | 68.32% | 46.35% | 103 | 41 |
| Extra trees | All recorded features | 73.78% | 67.58% | 51.04% | 94 | 67 |

## Decision

No candidate is a clear, safe replacement for the existing Prolog predictor:

- Logistic regression has the highest accuracy (80.94%) and balanced accuracy (70.81%) in this comparison, but rejection specificity is only 43.75%. It also produced 108 incorrect approvals across the full 614-row out-of-fold evaluation.
- The Prolog Naive Bayes replica scored 79.15% accuracy and 69.79% balanced accuracy. It produced 106 incorrect approvals and 22 incorrect rejections across the same 614 rows.
- Random forest reduces incorrect approvals and improves rejection specificity, but at the cost of many more incorrect rejections and lower overall/balanced accuracy.
- Removing gender and marital status did not materially reduce performance in this benchmark. Because these are sensitive attributes, the system should not rely on them for real lending decisions without a proper fairness and legal review.

**Therefore the production Prolog algorithm has not been replaced based on these results.** The benchmark does not justify promising 90%+ accuracy or changing the 50% decision threshold just to improve a headline number.

## Important limitations

The Kaggle labels record past approval/rejection decisions; they do not record whether borrowers repaid loans. These results measure how well a model reproduces those historical labels, not whether an applicant will repay or whether a lending decision is fair.

The five-fold comparison is a model-selection estimate, not an independent final test. Keep any lecturer-provided out-of-sample dataset untouched for the final assessment. Model-estimated scores must not be described as calibrated real-world probabilities.

## Reproducibility

Run the benchmark from the repository root:

\`\`\`powershell
python -m pip install pandas numpy scikit-learn
python tools/model_benchmark.py
\`\`\`

The script writes \`benchmark-results.json\`. GitHub Actions runs it automatically when the benchmark script or dataset changes.
