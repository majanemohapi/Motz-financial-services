
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
        PropertyArea
    ].

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

    retractall(trained(_)),
    assertz(trained(TrainingRows)),

    evaluate_rows(TestRows, Metrics),

    retractall(model_stats(_)),
    assertz(model_stats(Metrics)),

    format('~nMODEL TRAINING COMPLETE~n'),
    format('Total labelled records: ~w~n', [Total]),
    format('Training records: ~w~n', [TrainingCount]),
    format('Holdout records: ~w~n', [TestCount]),
    format('Holdout accuracy: ~2f%~n', [Metrics.accuracy]).

% Every fifth record is used for holdout testing.
split_dataset(Rows, Training, Test) :-
    split_dataset(Rows, 1, Training, Test).

split_dataset([], _, [], []).

split_dataset([Row|Rows], Index, Training, Test) :-

    (0 is Index mod 5
    -> Test = [Row|RestTest],
       Training = RestTraining
    ; Training = [Row|RestTraining],
      Test = RestTest),

    NextIndex is Index + 1,

    split_dataset(
        Rows,
        NextIndex,
        RestTraining,
        RestTest
    ).

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

    Probability is (Count + 1) / (ClassCount + 4),

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

predict_features(Features, Prediction, Confidence) :-

    trained(Rows),

    class_count(Rows, approved, ApprovedCount),
    class_count(Rows, rejected, RejectedCount),

    ApprovedCount > 0,
    RejectedCount > 0,

    class_score(Rows, approved, Features, ApprovedScore),
    class_score(Rows, rejected, Features, RejectedScore),

    (ApprovedScore >= RejectedScore
    -> Prediction = approved,
       Difference is ApprovedScore - RejectedScore
    ; Prediction = rejected,
      Difference is RejectedScore - ApprovedScore),

    Confidence is 1 / (1 + exp(-Difference)).

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

    (Precision + Recall =:= 0
    -> F1 = 0
    ; F1 is 2 * Precision * Recall / (Precision + Recall)),

    Metrics = _{
        total: Total,
        accuracy: Accuracy,
        precision: Precision,
        recall: Recall,
        specificity: Specificity,
        f1: F1,
        tp: TP,
        tn: TN,
        fp: FP,
        fn: FN
    }.

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

    (model_stats(Metrics)
    -> Accuracy = Metrics.accuracy
    ; Accuracy = 0),

    reply_json_dict(_{
        total: Total,
        approved: Approved,
        rejected: Rejected,
        accuracy: Accuracy
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

    ConfidencePercent is Confidence * 100,

    format(string(ConfidenceText), '~1f%', [ConfidencePercent]),

    reply_json_dict(_{
        success: true,
        prediction: Prediction,
        confidence: ConfidenceText,
        confidence_note: 'Relative Naive Bayes score; not a calibrated probability.',
        notice: 'This prediction is decision support and must be reviewed by a human.'
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
        method: 'Ordered 80/20 holdout; every fifth row held out.'
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

start :-

    (server_started
    -> format('The Motz server is already running.~n')

    ; load_dataset,

      http_server(
          http_dispatch,
          [port(8080), ip(*)]
      ),

      assertz(server_started),

      format('~n==============================================~n'),
      format(' MOTZ FINANCIAL SERVICES SERVER~n'),
      format('==============================================~n'),
      format('Dashboard: http://localhost:8080~n'),
      format('Health: http://localhost:8080/api/health~n'),
      format('Records: http://localhost:8080/api/records~n'),
      format('Static directory: public/~n'),
      format('==============================================~n'),
      format('Press Ctrl+C to stop the server.~n'),

      thread_get_message(_)
    ).

:- initialization(start, main).
