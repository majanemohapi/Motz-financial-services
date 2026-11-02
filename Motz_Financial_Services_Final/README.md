# Motz Financial Services — Enterprise Loan Intelligence Platform

**Module:** DIAL3110 Fundamentals of Artificial Intelligence  
**Classifier / prediction engine:** SWI-Prolog (categorical Naive Bayes)  
**Dataset:** supplied Kaggle Loan Prediction training CSV (`data/train.csv`)  
**Application URL when running locally:** `http://localhost:8080`

## Project status and verification note

This package preserves the original Motz Prolog project and includes its supplied Kaggle CSV, an upgraded dashboard, data audit artifacts, report, and presentation. The browser/API design and dataset artifacts were inspected in this environment. The prediction routine was corrected to strip the actual class label before feature scoring, preventing target leakage during holdout evaluation. A Windows one-click launcher and a live API health check were added. **SWI-Prolog was not installed in the build environment, so the Prolog server could not be executed here. Do not represent the live Prolog API or its metric values as runtime-tested until you run the steps below on a Windows machine with SWI-Prolog installed.** The included source is the intended executable model; the UI displays metrics returned by that source, not hard-coded performance claims.

No lecturer-provided out-of-sample dataset is included or used. Do not copy that dataset into the project before presentation day.

## 1. Project structure

```text
Motz_Financial_Services_Final/
├── main.pl
├── data/
│   └── train.csv
├── public/
│   ├── index.html
│   ├── style.css
│   └── app.js
├── outputs/
│   ├── dataset_audit.json
│   ├── 01_loan_status_distribution.png
│   ├── 02_applicant_income_distribution.png
│   ├── 03_missing_values.png
│   └── 04_outcomes_by_property_area.png
├── reports/
│   ├── MODEL_CREATION.md
│   ├── REPORT_GUIDE.md
│   └── Academic_Report.docx
├── presentation/
│   └── Motz_Executive_Presentation.pptx
└── README.md
```

## 2. Requirements

- Windows 10/11
- SWI-Prolog for Windows (install from the official SWI-Prolog website)
- Visual Studio Code (recommended, optional)
- A modern browser
- Internet connection for the Chart.js CDN used by the dashboard

## 3. Run the system on Windows

**Recommended: one-click startup.** Extract the ZIP, install SWI-Prolog, then double-click `RUN_MOTZ.bat`. It checks that SWI-Prolog and `data/train.csv` exist, starts the Prolog server from the correct project folder, and opens the browser at `http://localhost:8080`. Keep the Prolog console window open while demonstrating the dashboard. Press `Ctrl+C` in that window to stop the server.

**VS Code alternative:** Open the extracted project folder (the folder containing `main.pl` and `data`), open Terminal → New Terminal, and run `swipl -q -s main.pl`. Then visit `http://localhost:8080`.

If `swipl` is not recognised, restart VS Code after installation or add the SWI-Prolog `bin` directory to the Windows PATH. Do not run `main.pl` from a different working directory: the relative paths `data/train.csv` and `public/` are intentional.

## 4. What the system is intended to do

- Load the exact supplied `train.csv` and validate its header.
- Treat blank fields as an explicit `missing` category/value rather than silently inventing applicant data.
- Normalize category text to lowercase and use consistent numeric bins during training, holdout evaluation, and prediction.
- Train a Naive Bayes classifier in SWI-Prolog.
- Use a deterministic ordered holdout: every fifth record is held out for internal testing; the other four fifths train the model.
- Return accuracy, precision, recall, specificity, F1 and confusion-matrix counts calculated from holdout predictions.
- Serve dashboard API endpoints for health, summary, prediction, record preview, performance, category analysis and missing-value counts.
- Show data-driven dashboard charts and a dataset audit JSON file.

## 5. Dataset facts from the supplied file

- 614 rows and 13 columns.
- 422 `Y` outcomes and 192 `N` outcomes.
- 149 missing cells across the seven fields with missing values.
- No exact duplicate rows and no duplicated `Loan_ID` values in the supplied file.
- `Credit_History` has 50 missing values; these are not evidence of either good or poor credit.

The dataset audit and figures under `outputs/` were generated from the supplied CSV. They are descriptive analyses, not model-performance claims. To regenerate them, install Python with pandas, matplotlib and numpy, then run `python scripts/dataset_audit.py` from the project root.

## 6. Evaluation and interpretation

The confusion matrix uses **approved (`Y`) as the positive class**:

- TP: actually approved and predicted approved
- TN: actually rejected and predicted rejected
- FP: actually rejected but predicted approved
- FN: actually approved but predicted rejected

- Accuracy = (TP + TN) / (TP + TN + FP + FN)
- Precision = TP / (TP + FP)
- Recall / sensitivity = TP / (TP + FN)
- Specificity = TN / (TN + FP)
- F1 = 2 × precision × recall / (precision + recall)

Zero denominators return 0 to avoid a runtime arithmetic error. The metrics are generated when the Prolog application starts. Confirm the live values and record a screenshot before final submission. The ordered split is reproducible but can be sensitive to row order; discuss this limitation in the report.

## 7. Important model and fairness limitations

This is an academic prototype using a public benchmark, not Motz Financial Services' proprietary applicant records. Naive Bayes assumes conditional independence between features, which is not fully realistic for financial data. The simple binning rules are baseline design choices, not optimized credit-risk thresholds. The relative class score is not a calibrated probability. Missingness can itself carry information and should be investigated rather than interpreted as a financial characteristic.

Do not use the prediction as an automatic lending decision. Human review, fair-lending assessment, explainability, privacy, security, legal review, and validation on representative local data would be required before any real-world deployment. Do not claim the model is unbiased, production-ready, or approved for lending.

## 8. GitHub upload

1. Create a new private repository first if the lecturer has not approved public release.
2. Review `data/train.csv` licensing and the assignment's dataset redistribution rules before committing it.
3. From the project root:

   ```powershell
   git init
   git add main.pl public README.md reports outputs presentation
   git status
   git commit -m "Prepare Motz loan prediction academic project"
   git branch -M main
   git remote add origin YOUR_REPOSITORY_URL
   git push -u origin main
   ```

4. Add `data/train.csv` only if redistribution is allowed by the dataset's license/terms and the course requirements. If not, document the official source and instruct the reviewer where to obtain it. Never upload the lecturer's separate out-of-sample dataset.

## 9. Final pre-submission checklist

- [ ] Install SWI-Prolog on the demonstration laptop.
- [ ] Launch using `RUN_MOTZ.bat` and confirm the browser opens.
- [ ] Run `swipl -q -s main.pl` from the project root.
- [ ] Confirm all API endpoints load and the prediction form returns a result.
- [ ] Record the actual live performance metrics and confusion matrix.
- [ ] Verify all five dashboard visualisations render.
- [ ] Take genuine screenshots of the running application for the report.
- [ ] Confirm the academic report follows the lecturer's required page count and marking rubric.
- [ ] Replace group member placeholders with real names and agreed responsibilities.
- [ ] Keep the lecturer's out-of-sample dataset completely separate until presentation day.
