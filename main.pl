
% ============================================================
% MOTZ FINANCIAL SERVICES
% LOAN PREDICTION SYSTEM
% SWI-PROLOG WEB APPLICATION
% ============================================================

:- use_module(library(http/thread_httpd)).
:- use_module(library(http/http_dispatch)).
:- use_module(library(http/http_files)).
:- use_module(library(http/http_json)).
:- use_module(library(csv)).
:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(pairs)).
:- use_module(library(error)).
:- use_module(library(random)).

:- dynamic loan/13.
:- dynamic trained/1.
:- dynamic model_stats/1.
:- dynamic public_directory/1.
:- dynamic dataset_path/1.
:- dynamic server_started/0.

% ============================================================
% PROJECT DIRECTORIES
% ============================================================

:- prolog_load_context(directory, ProjectDir),
   directory_file_path(ProjectDir, 'public', PublicDir),
   directory_file_path(ProjectDir, 'data/train.csv', DatasetFile),
   assertz(public_directory(PublicDir)),
   assertz(dataset_path(DatasetFile)).

% ============================================================
% HTTP ROUTES
% ============================================================

:- http_handler(root(api/health), api_health, []).
:- http_handler(root(api/summary), api_summary, []).
:- http_handler(root(api/predict), api_predict, []).
:- http_handler(root(api/records), api_records, []).
:- http_handler(root(api/performance), api_performance, []).
:- http_handler(root(api/analysis), api_analysis, []).
:- http_handler(root(api/data_quality), api_data_quality, []).

:- http_handler(root(.), serve_public, [prefix]).

% ============================================================
% STATIC WEBSITE
% ============================================================

serve_public(Request) :-
    public_directory(PublicDir),
    http_reply_from_files(
        PublicDir,
        [indexes(['index.html'])],
        Request
    ).

% ============================================================
% DATASET LOADING
% ============================================================

load_dataset :-
    retractall(loan(_,_,_,_,_,_,_,_,_,_,_,_,_)),
    retractall(trained(_)),
    retractall(model_stats(_)),

    dataset_path(File),

    (exists_file(File)
    -> true
    ; throw(error(existence_error(file, File), _))),

    csv_read_file(
        File,
        Rows,
        [functor(row), arity(13), strip(true), convert(true)]
    ),

    validate_dataset(Rows, DataRows),

    maplist(assert_loan, DataRows),

    count_status(approved, Approved),
    count_status(rejected, Rejected),

    Total is Approved + Rejected,

    (Total > 0
    -> true
    ; throw(error(domain_error(dataset, empty), _))),

    format('~n==============================================~n'),
    format(' MOTZ FINANCIAL SERVICES: LOAN PREDICTION~n'),
    format('==============================================~n'),
    format('Dataset loaded successfully.~n'),
    format('Total applications: ~w~n', [Total]),
    format('Approved applications: ~w~n', [Approved]),
    format('Rejected applications: ~w~n', [Rejected]),
    format('==============================================~n'),

    train_and_evaluate.

validate_dataset([Header|Rows], DataRows) :-

    Header =.. [_|Columns],

    Expected = [
        'Loan_ID',
        'Gender',
        'Married',
        'Dependents',
        'Education',
        'Self_Employed',
        'ApplicantIncome',
        'CoapplicantIncome',
        'LoanAmount',
        'Loan_Amount_Term',
        'Credit_History',
        'Property_Area',
        'Loan_Status'
    ],

    (Columns == Expected
    -> exclude(invalid_row, Rows, DataRows)
    ; throw(error(
        domain_error(dataset_headers, Columns),
        context(load_dataset/0, 'Unexpected CSV headings')
    ))).

validate_dataset([], _) :-
    throw(error(domain_error(dataset, empty_file), _)).

invalid_row(Row) :-
    Row =.. [_|Values],
    length(Values, Length),
    Length =\= 13.

% ============================================================
% DATA CLEANING
% ============================================================

value_atom(Value, Atom) :-
    (atom(Value)
    -> Atom = Value
    ; string(Value)
    -> atom_string(Atom, Value)
    ; number(Value)
    -> atom_number(Atom, Value)
    ; Atom = '').

normalize_text(Value, Result) :-
    value_atom(Value, Atom0),
    normalize_space(atom(Atom1), Atom0),
    downcase_atom(Atom1, Lower),
    (Lower == '' -> Result = missing ; Result = Lower).

clean_category(Value, Result) :-
    normalize_text(Value, Normalized),
    (memberchk(Normalized, [missing, na, null, 'n/a', '?'])
    -> Result = missing
    ; Normalized == not_graduate
    -> Result = 'not graduate'
    ; Result = Normalized).

clean_dependents(Value, Result) :-
    normalize_text(Value, Normalized),
    (memberchk(Normalized, [missing, na, null, 'n/a', '?'])
    -> Result = missing
    ; memberchk(Normalized, ['3', '3+'])
    -> Result = dep_3_plus
    ; Result = Normalized).

number_or_missing(Value, Result) :-
    (number(Value)
    -> Result = Value
    ; value_atom(Value, Atom),
      catch(atom_number(Atom, Number), _, fail)
    -> Result = Number
    ; Result = missing).

normalize_credit_history(Value, Result) :-
    (number(Value), Value =:= 0
    -> Result = 0
    ; number(Value), Value =:= 1
    -> Result = 1
    ; Result = Value).

clean_status(Value, Result) :-
    normalize_text(Value, Normalized),
    (memberchk(Normalized, [y, yes, approved])
    -> Result = approved
    ; memberchk(Normalized, [n, no, rejected])
    -> Result = rejected
    ; throw(error(domain_error(loan_status, Value), _))).

assert_loan(Row) :-
    Row =.. [
        _,
        ID,
        Gender,
        Married,
        Dependents,
        Education,
        SelfEmployed,
        ApplicantIncome,
        CoapplicantIncome,
        LoanAmount,
        LoanTerm,
        CreditHistory,
        PropertyArea,
        LoanStatus
    ],

    normalize_text(ID, LoanID),
    clean_category(Gender, GenderValue),
    clean_category(Married, MarriedValue),
    clean_dependents(Dependents, DependentsValue),
    clean_category(Education, EducationValue),
    clean_category(SelfEmployed, SelfEmployedValue),

    number_or_missing(ApplicantIncome, ApplicantIncomeValue),
    number_or_missing(CoapplicantIncome, CoapplicantIncomeValue),
    number_or_missing(LoanAmount, LoanAmountValue),
    number_or_missing(LoanTerm, LoanTermValue),
    number_or_missing(CreditHistory, CreditHistoryRaw),

    normalize_credit_history(CreditHistoryRaw, CreditHistoryValue),

    clean_category(PropertyArea, PropertyAreaValue),
    clean_status(LoanStatus, Status),

    assertz(loan(
        LoanID,
        GenderValue,
        MarriedValue,
        DependentsValue,
        EducationValue,
        SelfEmployedValue,
        ApplicantIncomeValue,
        CoapplicantIncomeValue,
        LoanAmountValue,
        LoanTermValue,
        CreditHistoryValue,
        PropertyAreaValue,
        Status
    )).

% ============================================================
% FEATURE ENGINEERING
% ============================================================

income_band(missing, missing).
income_band(Value, low) :-
    number(Value), Value < 2500, !.
income_band(Value, medium) :-
    number(Value), Value < 6000, !.
income_band(Value, high) :-
    number(Value), Value < 12000, !.
income_band(Value, very_high) :-
    number(Value).

co_income_band(missing, missing).
co_income_band(Value, none) :-
    number(Value), Value =:= 0, !.
co_income_band(Value, low) :-
    number(Value), Value < 2000, !.
co_income_band(Value, medium) :-
    number(Value), Value < 5000, !.
co_income_band(Value, high) :-
    number(Value).

loan_amount_band(missing, missing).
loan_amount_band(Value, low) :-
    number(Value), Value < 100, !.
loan_amount_band(Value, medium) :-
    number(Value), Value < 200, !.
loan_amount_band(Value, high) :-
    number(Value), Value < 350, !.
loan_amount_band(Value, very_high) :-
    number(Value).

term_band(missing, missing).
term_band(Value, short) :-
    number(Value), Value < 180, !.
term_band(Value, standard) :-
    number(Value), Value =< 360, !.
term_band(Value, long) :-
    number(Value).

loan_features(
    Gender, Married, Dependents, Education, SelfEmployed,
    ApplicantIncome, CoapplicantIncome, LoanAmount, LoanTerm,
    CreditHistory, PropertyArea, Features
) :-

    income_band(ApplicantIncome, ApplicantBand),
    co_income_band(CoapplicantIncome, CoApplicantBand),
    loan_amount_band(LoanAmount, LoanAmountBand),
    term_band(LoanTerm, TermBand),
    repayment_burden_band(
        ApplicantIncome,
        CoapplicantIncome,
        LoanAmount,
        LoanTerm,
        RepaymentBurdenBand
    ),

    Features = [
        Gender,
        Married,
        Dependents,
        Education,
        SelfEmployed,
        ApplicantBand,
        CoApplicantBand,
        LoanAmountBand,
        TermBand,
        CreditHistory,
        PropertyArea,
        RepaymentBurdenBand
    ].

% Derived feature: estimated monthly principal repayment divided by
% combined monthly income. Kaggle LoanAmount is expressed in thousands.
% This uses only fields already present in train.csv and the application form.
repayment_burden_band(ApplicantIncome, CoapplicantIncome, LoanAmount, LoanTerm, Band) :-
    ( number(ApplicantIncome),
      number(CoapplicantIncome),
      number(LoanAmount),
      number(LoanTerm),
      LoanTerm > 0,
      TotalIncome is ApplicantIncome + CoapplicantIncome,
      TotalIncome > 0
    -> MonthlyPrincipal is (LoanAmount * 1000) / LoanTerm,
       Burden is MonthlyPrincipal / TotalIncome,
       ( Burden =< 0.15 -> Band = low
       ; Burden =< 0.30 -> Band = moderate
       ; Burden =< 0.50 -> Band = high
       ; Band = very_high
       )
    ; Band = missing
    ).

loan_to_features(
    loan(
        _,
        Gender, Married, Dependents, Education, SelfEmployed,
        ApplicantIncome, CoapplicantIncome, LoanAmount, LoanTerm,
        CreditHistory, PropertyArea, Status
    ),
    Features,
    Status
) :-

    loan_features(
        Gender, Married, Dependents, Education, SelfEmployed,
        ApplicantIncome, CoapplicantIncome, LoanAmount, LoanTerm,
        CreditHistory, PropertyArea, Features
    ).

% ============================================================
% LOAN RECORD RETRIEVAL
% THIS PREDICATE FIXES THE MISSING loan_record/1 ERROR
% ============================================================

loan_record(
    loan(
        ID,
        Gender,
        Married,
        Dependents,
        Education,
        SelfEmployed,
        ApplicantIncome,
        CoapplicantIncome,
        LoanAmount,
        LoanTerm,
        CreditHistory,
        PropertyArea,
        Status
    )
) :-

    loan(
        ID,
        Gender,
        Married,
        Dependents,
        Education,
        SelfEmployed,
        ApplicantIncome,
        CoapplicantIncome,
        LoanAmount,
        LoanTerm,
        CreditHistory,
        PropertyArea,
        Status
    ).

% ============================================================
% TRAINING AND TESTING
% ============================================================

train_and_evaluate :-

    findall(
        Features-Status,
        (
            loan_record(Loan),
            loan_to_features(Loan, Features, Status)
        ),
        AllRows
    ),

    split_dataset(AllRows, TrainingRows, TestRows),

    length(AllRows, Total),
    length(TrainingRows, TrainingCount),
    length(TestRows, TestCount),

    (TrainingCount > 0
    -> true
    ; throw(error(domain_error(training_dataset, empty), _))),

    class_count(TrainingRows, approved, ApprovedCount),
    class_count(TrainingRows, rejected, RejectedCount),

    (ApprovedCount > 0, RejectedCount > 0
    -> true
    ; throw(error(domain_error(training_classes,
        ApprovedCount-RejectedCount), _))),

    % First fit only on the training partition and evaluate on unseen
    % holdout rows. Never train on the holdout before calculating metrics.
    retractall(trained(_)),
    assertz(trained(TrainingRows)),
    evaluate_rows(TestRows, HoldoutMetrics),

    % After the honest holdout evaluation, refit the production model on
    % every labelled CSV row so no training examples are unnecessarily lost.
    retractall(trained(_)),
    assertz(trained(AllRows)),

    put_dict(
        _{training_records: Total, holdout_records: TestCount},
        HoldoutMetrics,
        Metrics
    ),

    retractall(model_stats(_)),
    assertz(model_stats(Metrics)),

    format('~nMODEL TRAINING COMPLETE~n'),
    format('Total labelled records: ~w~n', [Total]),
    format('Training records used for holdout evaluation: ~w~n', [TrainingCount]),
    format('Holdout records: ~w~n', [TestCount]),
    format('Final production training records: ~w~n', [Total]),
    format('Holdout accuracy: ~2f%~n', [Metrics.accuracy]).

% Reproducible stratified 80/20 holdout: each class is shuffled
% independently so both approved and rejected records are represented.
split_dataset(Rows, Training, Test) :-
    set_random(seed(20261116)),
    include(has_class(approved), Rows, ApprovedRows),
    include(has_class(rejected), Rows, RejectedRows),
    random_permutation(ApprovedRows, ShuffledApproved),
    random_permutation(RejectedRows, ShuffledRejected),
    split_class_rows(ShuffledApproved, ApprovedTraining, ApprovedTest),
    split_class_rows(ShuffledRejected, RejectedTraining, RejectedTest),
    append(ApprovedTraining, RejectedTraining, Training),
    append(ApprovedTest, RejectedTest, Test).

split_class_rows(Rows, Training, Test) :-
    length(Rows, Count),
    TestCount is max(1, (Count + 4) // 5),
    TrainingCount is Count - TestCount,
    length(Training, TrainingCount),
    append(Training, Test, Rows).

% ============================================================
% NAIVE BAYES CLASSIFIER
% ============================================================

class_count(Rows, Class, Count) :-
    include(has_class(Class), Rows, Matching),
    length(Matching, Count).

has_class(Class, _-Class).

feature_count(Rows, Class, Position, Value, Count) :-
    include(
        has_feature(Class, Position, Value),
        Rows,
        Matching
    ),
    length(Matching, Count).

has_feature(Class, Position, Value, Features-Class) :-
    nth1(Position, Features, FeatureValue),
    FeatureValue == Value.

class_score(Rows, Class, Features, Score) :-

    class_count(Rows, Class, ClassCount),
    length(Rows, Total),

    Total > 0,
    ClassCount > 0,

    % Use the actual class distribution in the training data.
    Prior is log(ClassCount / Total),

    feature_score(
        Rows,
        Class,
        Features,
        1,
        ClassCount,
        FeatureScore
    ),

    Score is Prior + FeatureScore.

feature_score(_, _, [], _, _, 0).

feature_score(
    Rows,
    Class,
    [Value|Values],
    Position,
    ClassCount,
    Score
) :-

    feature_count(
        Rows,
        Class,
        Position,
        Value,
        Count
    ),

    feature_domain_size(Position, DomainSize),
    Probability is (Count + 1) / (ClassCount + DomainSize),

    PartScore is log(Probability),

    NextPosition is Position + 1,

    feature_score(
        Rows,
        Class,
        Values,
        NextPosition,
        ClassCount,
        RemainingScore
    ),

    Score is PartScore + RemainingScore.

% Number of possible values for each categorical feature.
% These include the missing-value category used during data cleaning.
feature_domain_size(1, 3).   % Gender
feature_domain_size(2, 3).   % Married
feature_domain_size(3, 5).   % Dependents
feature_domain_size(4, 3).   % Education
feature_domain_size(5, 3).   % Self employed
feature_domain_size(6, 5).   % Applicant income band
feature_domain_size(7, 5).   % Co-applicant income band
feature_domain_size(8, 5).   % Loan amount band
feature_domain_size(9, 4).   % Loan term band
feature_domain_size(10, 3).  % Credit history
feature_domain_size(11, 4).  % Property area
feature_domain_size(12, 5).  % Estimated repayment burden band

predict_features(Features, Prediction, Confidence) :-

    trained(Rows),

    class_count(Rows, approved, ApprovedCount),
    class_count(Rows, rejected, RejectedCount),

    ApprovedCount > 0,
    RejectedCount > 0,

    class_score(Rows, approved, Features, ApprovedScore),
    class_score(Rows, rejected, Features, RejectedScore),

    % Approval likelihood is compared with the requested 50% decision threshold.
    % At 50% or above the model predicts approved; below 50% it predicts rejected.
    ApprovalDifference is ApprovedScore - RejectedScore,
    ApprovalLikelihood is 1 / (1 + exp(-ApprovalDifference)),

    (ApprovalLikelihood >= 0.5
    -> Prediction = approved,
       Confidence = ApprovalLikelihood
    ; Prediction = rejected,
      Confidence is 1 - ApprovalLikelihood).

% ============================================================
% MODEL EVALUATION
% ============================================================

evaluate_rows(TestRows, Metrics) :-

    evaluate_rows(
        TestRows,
        0, 0, 0, 0,
        TP, TN, FP, FN
    ),

    Total is TP + TN + FP + FN,

    safe_percentage(TP + TN, Total, Accuracy),
    safe_percentage(TP, TP + FP, Precision),
    safe_percentage(TP, TP + FN, Recall),
    safe_percentage(TN, TN + FP, Specificity),
    BalancedAccuracy is (Recall + Specificity) / 2,

    (Precision + Recall =:= 0
    -> F1 = 0
    ; F1 is 2 * Precision * Recall / (Precision + Recall)),

    % Probability-quality metrics are calculated on the same unseen
    % holdout rows. Brier score and log loss penalize overconfident errors.
    probability_metrics(TestRows, BrierScore, LogLoss),

    Metrics = _{
        total: Total,
        accuracy: Accuracy,
        precision: Precision,
        recall: Recall,
        specificity: Specificity,
        balanced_accuracy: BalancedAccuracy,
        f1: F1,
        brier_score: BrierScore,
        log_loss: LogLoss,
        tp: TP,
        tn: TN,
        fp: FP,
        fn: FN
    }.

probability_metrics(Rows, BrierScore, LogLoss) :-
    probability_metrics(Rows, 0.0, 0.0, Count, BrierTotal, LogLossTotal),
    ( Count > 0
    -> BrierScore is BrierTotal / Count,
       LogLoss is LogLossTotal / Count
    ; BrierScore = 0.0,
      LogLoss = 0.0
    ).

probability_metrics([], BrierAcc, LogAcc, 0, BrierAcc, LogAcc).
probability_metrics([Features-Actual|Rows], BrierAcc, LogAcc, Count, BrierTotal, LogLossTotal) :-
    predict_features(Features, Predicted, Confidence),
    ( Predicted == Actual
    -> ActualProbability = Confidence
    ; ActualProbability is 1.0 - Confidence
    ),
    Error is ActualProbability - 1.0,
    BrierNext is BrierAcc + Error * Error,
    ClampedProbability is max(1.0e-15, min(1.0 - 1.0e-15, ActualProbability)),
    LogNext is LogAcc - log(ClampedProbability),
    probability_metrics(Rows, BrierNext, LogNext, Remaining, BrierTotal, LogLossTotal),
    Count is Remaining + 1.

evaluate_rows([], TP, TN, FP, FN, TP, TN, FP, FN).

evaluate_rows(
    [Features-Actual|Rows],
    TP0, TN0, FP0, FN0,
    TP, TN, FP, FN
) :-

    predict_features(Features, Predicted, _),

    update_confusion(
        Actual,
        Predicted,
        TP0, TN0, FP0, FN0,
        TP1, TN1, FP1, FN1
    ),

    evaluate_rows(
        Rows,
        TP1, TN1, FP1, FN1,
        TP, TN, FP, FN
    ).

update_confusion(approved, approved, TP, TN, FP, FN,
                 NewTP, TN, FP, FN) :-
    NewTP is TP + 1.

update_confusion(rejected, rejected, TP, TN, FP, FN,
                 TP, NewTN, FP, FN) :-
    NewTN is TN + 1.

update_confusion(rejected, approved, TP, TN, FP, FN,
                 TP, TN, NewFP, FN) :-
    NewFP is FP + 1.

update_confusion(approved, rejected, TP, TN, FP, FN,
                 TP, TN, FP, NewFN) :-
    NewFN is FN + 1.

safe_percentage(_Numerator, Denominator, 0) :-
    EvaluatedDenominator is Denominator,
    EvaluatedDenominator =:= 0,
    !.

safe_percentage(Numerator, Denominator, Percentage) :-
    EvaluatedDenominator is Denominator,
    Percentage is (Numerator / EvaluatedDenominator) * 100.

% ============================================================
% API: HEALTH
% ============================================================

api_health(_Request) :-

    count_status(approved, Approved),
    count_status(rejected, Rejected),

    Total is Approved + Rejected,

    reply_json_dict(_{
        status: ok,
        application: 'Motz Financial Services Loan Prediction',
        engine: 'SWI-Prolog',
        records: Total
    }).

% ============================================================
% API: SUMMARY
% ============================================================

api_summary(_Request) :-

    count_status(approved, Approved),
    count_status(rejected, Rejected),

    Total is Approved + Rejected,

    safe_percentage(Approved, Total, ApprovalRate),
    safe_percentage(Rejected, Total, RejectionRate),

    (model_stats(Metrics)
    -> Accuracy = Metrics.accuracy
    ; Accuracy = 0),

    reply_json_dict(_{
        total: Total,
        approved: Approved,
        rejected: Rejected,
        approval_rate: ApprovalRate,
        rejection_rate: RejectionRate,
        accuracy: Accuracy,
        rate_source: 'Loaded data/train.csv Loan_Status labels'
    }).

count_status(Status, Count) :-
    findall(
        1,
        loan(_,_,_,_,_,_,_,_,_,_,_,_,Status),
        Rows
    ),
    length(Rows, Count).

% ============================================================
% API: LOAN PREDICTION
% ============================================================

api_predict(Request) :-
    catch(
        api_predict_request(Request),
        Error,
        api_predict_error(Error)
    ).

api_predict_request(Request) :-

    http_read_json_dict(Request, Input),

    get_input(Input, gender, male, Gender0),
    get_input(Input, married, yes, Married0),
    get_input(Input, dependents, '0', Dependents0),
    get_input(Input, education, graduate, Education0),
    get_input(Input, selfEmployed, no, SelfEmployed0),

    get_input(Input, applicantIncome, 5000, ApplicantIncome0),
    get_input(Input, coapplicantIncome, 0, CoapplicantIncome0),
    get_input(Input, loanAmount, 120, LoanAmount0),
    get_input(Input, loanTerm, 360, LoanTerm0),
    get_input(Input, creditHistory, 1, CreditHistory0),

    get_input(Input, propertyArea, urban, PropertyArea0),

    clean_category(Gender0, Gender),
    clean_category(Married0, Married),
    clean_dependents(Dependents0, Dependents),
    clean_category(Education0, Education),
    clean_category(SelfEmployed0, SelfEmployed),

    number_or_missing(ApplicantIncome0, ApplicantIncome),
    number_or_missing(CoapplicantIncome0, CoapplicantIncome),
    number_or_missing(LoanAmount0, LoanAmount),
    number_or_missing(LoanTerm0, LoanTerm),
    number_or_missing(CreditHistory0, CreditHistoryRaw),

    normalize_credit_history(CreditHistoryRaw, CreditHistory),

    clean_category(PropertyArea0, PropertyArea),

    validate_prediction_input(
        ApplicantIncome,
        CoapplicantIncome,
        LoanAmount,
        LoanTerm,
        CreditHistory
    ),

    loan_features(
        Gender, Married, Dependents, Education, SelfEmployed,
        ApplicantIncome, CoapplicantIncome, LoanAmount, LoanTerm,
        CreditHistory, PropertyArea, Features
    ),

    (predict_features(Features, Prediction, Confidence)
    -> true
    ; throw(error(
        prediction_failed,
        context(api_predict/1, 'The model is not trained or is missing a class.')
    ))),

    % Convert the two Naive Bayes log scores into a model posterior.
    % This is the probability implied by the model assumptions, not a
    % statistically calibrated real-world lending probability.
    ConfidencePercent is Confidence * 100,
    (Prediction == approved
    -> ApprovalLikelihood = ConfidencePercent,
       RejectionLikelihood is 100 - ConfidencePercent
    ; RejectionLikelihood = ConfidencePercent,
      ApprovalLikelihood is 100 - ConfidencePercent),

    format(string(ConfidenceText), '~1f%', [ConfidencePercent]),

    reply_json_dict(_{
        success: true,
        prediction: Prediction,
        confidence: ConfidenceText,
        approval_likelihood: ApprovalLikelihood,
        rejection_likelihood: RejectionLikelihood,
        confidence_note: 'Model-estimated likelihood from Naive Bayes class scores. It is not independently calibrated and is not a guarantee of approval.',
        review_required: true,
        notice: 'This is an estimate based on historical Kaggle records. A qualified human must review the application before any lending decision.'
    }).

api_predict_error(Error) :-

    message_to_string(Error, ErrorMessage),

    format(user_error,
        'Prediction request failed: ~w~n',
        [ErrorMessage]),

    reply_json_dict(
        _{
            success: false,
            error: ErrorMessage
        },
        [status(400)]
    ).

get_input(Dict, Key, Default, Value) :-
    (get_dict(Key, Dict, Found)
    -> Value = Found
    ; Value = Default).

validate_prediction_input(A, C, L, T, H) :-

    must_be_nonnegative_number(A, applicantIncome),
    must_be_nonnegative_number(C, coapplicantIncome),
    must_be_nonnegative_number(L, loanAmount),
    must_be_positive_number(T, loanTerm),

    (memberchk(H, [0, 1])
    -> true
    ; throw(error(domain_error(credit_history, H), _))).

must_be_nonnegative_number(Value, _) :-
    number(Value),
    Value >= 0,
    !.

must_be_nonnegative_number(Value, Field) :-
    throw(error(
        domain_error(nonnegative_number, Field-Value),
        _
    )).

must_be_positive_number(Value, _) :-
    number(Value),
    Value > 0,
    !.

must_be_positive_number(Value, Field) :-
    throw(error(
        domain_error(positive_number, Field-Value),
        _
    )).

% ============================================================
% API: DATASET RECORDS
% ============================================================

api_records(_Request) :-

    findall(
        _{
            loan_id: ID,
            gender: Gender,
            married: Married,
            dependents: Dependents,
            education: Education,
            status: Status
        },

        loan(
            ID,
            Gender,
            Married,
            Dependents,
            Education,
            _,
            _,
            _,
            _,
            _,
            _,
            _,
            Status
        ),

        AllRecords
    ),

    first_ten(AllRecords, Records),

    length(AllRecords, Total),

    reply_json_dict(_{
        total: Total,
        records: Records
    }).

first_ten(List, FirstTen) :-
    length(FirstTen, 10),
    append(FirstTen, _, List),
    !.

first_ten(List, List).

% ============================================================
% API: MODEL PERFORMANCE
% ============================================================

api_performance(_Request) :-

    (model_stats(Metrics)
    -> reply_json_dict(_{
        metrics: Metrics,
        confusion: _{
            tp: Metrics.tp,
            tn: Metrics.tn,
            fp: Metrics.fp,
            fn: Metrics.fn
        },
        method: 'Reproducible stratified 80/20 holdout evaluation; final production model refitted on all labelled CSV rows; natural class priors; Laplace smoothing; derived repayment-burden feature; holdout Brier score and log loss assess probability quality.'
    })
    ; reply_json_dict(_{
        error: 'Model evaluation is not available.'
    })).

% ============================================================
% API: DATA ANALYSIS
% ============================================================

api_analysis(_Request) :-

    category_analysis(gender, GenderAnalysis),
    category_analysis(education, EducationAnalysis),
    property_analysis(PropertyAnalysis),

    reply_json_dict(_{
        gender: GenderAnalysis,
        education: EducationAnalysis,
        property: PropertyAnalysis
    }).

category_analysis(gender, Analysis) :-
    category_counts(2, [male, female], Analysis).

category_analysis(education, Analysis) :-
    category_counts(5, [graduate, 'not graduate'], Analysis).

category_counts(Position, Categories, Analysis) :-
    maplist(
        category_result(Position),
        Categories,
        Analysis
    ).

category_result(Position, Category, _{
    label: Category,
    approved: Approved,
    rejected: Rejected
}) :-

    count_category(Position, Category, approved, Approved),
    count_category(Position, Category, rejected, Rejected).

count_category(Position, Category, Status, Count) :-

    findall(
        1,
        (
            loan(
                _, Gender, Married, Dependents, Education, SelfEmployed,
                ApplicantIncome, CoapplicantIncome, LoanAmount, LoanTerm,
                CreditHistory, PropertyArea, Status
            ),

            Values = [
                _,
                Gender,
                Married,
                Dependents,
                Education,
                SelfEmployed,
                ApplicantIncome,
                CoapplicantIncome,
                LoanAmount,
                LoanTerm,
                CreditHistory,
                PropertyArea
            ],

            nth1(Position, Values, Category)
        ),
        Matches
    ),

    length(Matches, Count).

property_analysis(Analysis) :-

    property_result(urban, Urban),
    property_result(semiurban, Semiurban),
    property_result(rural, Rural),

    Analysis = [Urban, Semiurban, Rural].

property_result(Area, _{
    label: Area,
    approved: Approved,
    rejected: Rejected
}) :-

    count_property(Area, approved, Approved),
    count_property(Area, rejected, Rejected).

count_property(Area, Status, Count) :-
    findall(
        1,
        loan(_,_,_,_,_,_,_,_,_,_,_,Area,Status),
        Matches
    ),
    length(Matches, Count).

% ============================================================
% API: DATA QUALITY
% ============================================================

api_data_quality(_Request) :-

    missing_count(2, Gender),
    missing_count(3, Married),
    missing_count(4, Dependents),
    missing_count(6, SelfEmployed),
    missing_count(9, LoanAmount),
    missing_count(10, LoanTerm),
    missing_count(11, CreditHistory),

    reply_json_dict(_{
        labels: [
            'Gender',
            'Married',
            'Dependents',
            'Self Employed',
            'Loan Amount',
            'Loan Term',
            'Credit History'
        ],
        values: [
            Gender,
            Married,
            Dependents,
            SelfEmployed,
            LoanAmount,
            LoanTerm,
            CreditHistory
        ]
    }).

missing_count(Position, Count) :-

    findall(
        1,
        (
            loan(
                _,
                Gender,
                Married,
                Dependents,
                _,
                SelfEmployed,
                _,
                _,
                LoanAmount,
                LoanTerm,
                CreditHistory,
                _,
                _
            ),

            Values = [
                _,
                Gender,
                Married,
                Dependents,
                _,
                SelfEmployed,
                _,
                _,
                LoanAmount,
                LoanTerm,
                CreditHistory
            ],

            nth1(Position, Values, missing)
        ),
        Matches
    ),

    length(Matches, Count).

% ============================================================
% START WEB SERVER
% ============================================================

server_port(Port) :-
    ( getenv('PORT', PortAtom), atom_number(PortAtom, ParsedPort)
    -> Port = ParsedPort
    ;  Port = 8080
    ).

start :-

    (server_started
    -> format('The Motz server is already running.~n')

    ; load_dataset,

      server_port(Port),
      http_server(
          http_dispatch,
          [port(Port), ip(*)]
      ),

      assertz(server_started),

      format('~n==============================================~n'),
      format(' MOTZ FINANCIAL SERVICES SERVER~n'),
      format('==============================================~n'),
      format('Dashboard port: ~w~n', [Port]),
      format('Health endpoint: /api/health~n'),
      format('Records endpoint: /api/records~n'),
      format('Static directory: public/~n'),
      format('==============================================~n'),
      format('Press Ctrl+C to stop the server.~n'),

      thread_get_message(_)
    ).

:- initialization(start, main).
