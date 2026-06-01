/* ============================================================
   Framingham CHD -- Table 1 and Logistic Regression
   Rohit Kambala | May 2026

   Dataset: framingham_fixed.csv (4240 obs, 16 vars)
   Goal: reproduce R logistic regression in SAS and build
   a submission-quality TLF-style Table 1.

   Key decisions documented here:
   - Six variables came in as character due to NA strings in CSV.
     All converted to numeric in one clean DATA step below.
   - diaBP dropped from logistic model: r=0.78 with sysBP,
     coefficient non-significant (p=0.63) and biologically
     counterintuitive. PROC CORR documents the exclusion decision.
   - 438 obs dropped by PROC LOGISTIC due to missing values.
     That is 10% of the dataset. Worth a proper missing data
     audit before this goes anywhere near a submission.
   - Table 1 uses pre-aggregation pattern: all string formatting
     done in PROC SQL before PROC REPORT. COMPUTE block string
     assembly inside PROC REPORT is unreliable -- avoid it.
   ============================================================ */


/* ---- Step 1: Import ----------------------------------------
   GUESSINGROWS=4240 forces SAS to scan the whole file before
   deciding variable types. Without this, SAS reads only the
   first 20 rows by default. glucose has NA strings scattered
   throughout, so the default scan misclassifies it as character.
   Setting GUESSINGROWS to the full N fixes that at import.
   ------------------------------------------------------------ */
PROC IMPORT DATAFILE="/home/u64518804/framingham_fixed.csv"
    OUT=work.framingham DBMS=CSV REPLACE;
    GETNAMES=YES;
    GUESSINGROWS=4240;
RUN;


/* ---- Step 2: Fix character variables -----------------------
   Six variables came in as character: glucose, cigsPerDay,
   education, BPMeds, totChol, BMI, heartRate.

   This happens because even one non-numeric value in a column
   (an empty string, "NA", or a stray letter) causes SAS to
   call the whole column character. Cannot change its mind later.

   INPUT(var, 8.) reads a character value and returns numeric.
   Any true NA strings become SAS missing (.) automatically.
   DROP the original character version, RENAME the new one back.

   Doing all conversions in one DATA step rather than chaining
   multiple steps -- cleaner and faster.
   ------------------------------------------------------------ */
DATA work.framingham_clean;
    SET work.framingham;

    glucose_num    = INPUT(glucose,    8.);
    cigsPerDay_num = INPUT(cigsPerDay, 8.);
    education_num  = INPUT(education,  8.);
    BPMeds_num     = INPUT(BPMeds,     8.);
    totChol_num    = INPUT(totChol,    8.);
    BMI_num        = INPUT(BMI,        8.);
    heartRate_num  = INPUT(heartRate,  8.);

    DROP glucose cigsPerDay education BPMeds totChol BMI heartRate;

    RENAME glucose_num    = glucose
           cigsPerDay_num = cigsPerDay
           education_num  = education
           BPMeds_num     = BPMeds
           totChol_num    = totChol
           BMI_num        = BMI
           heartRate_num  = heartRate;
RUN;


/* ---- Step 3: Sanity check on glucose -----------------------
   Expecting N around 3852 (some missing) and NMISS around 388.
   If these numbers look off, the INPUT conversion above went wrong.
   ------------------------------------------------------------ */
PROC MEANS DATA=work.framingham_clean N NMISS MIN MAX;
    VAR glucose;
    TITLE 'Glucose: quick check after character-to-numeric conversion';
RUN;


/* ---- Step 4: Correlation check -- sysBP vs diaBP -----------
   In the full logistic model, diaBP came out non-significant
   (p=0.63) and its coefficient flipped negative, which is
   biologically counterintuitive. Strong suspicion: sysBP and
   diaBP are correlated enough that once sysBP is in the model,
   diaBP has nothing left to explain.

   PROC CORR quantifies this. If Pearson r > 0.7, multicollinearity
   is the likely explanation and dropping diaBP is justified.
   Documenting this step so the variable exclusion decision
   has an audit trail -- important habit for pharma work.

   Result (May 2026): r = 0.784. diaBP dropped from final model.
   ------------------------------------------------------------ */
PROC CORR DATA=work.framingham_clean NOSIMPLE;
    VAR sysBP diaBP;
    TITLE 'Correlation: sysBP vs diaBP -- checking multicollinearity';
RUN;


/* ---- Step 5: Logistic regression -- final model ------------
   DESCENDING: models P(TenYearCHD=1), not P(TenYearCHD=0).
   Always check the Response Profile table to confirm SAS is
   modeling the event you actually want. Easy mistake to miss.

   CLASS male (REF='0'): female is the reference category.
   PARAM=REF gives a single indicator for male=1 vs male=0,
   which is what you want for a binary variable.

   SELECTION=NONE: no automated variable selection. In a real
   clinical submission, variable inclusion is pre-specified in
   the SAP. Stepwise selection is not acceptable to regulators.

   CLODDS=PL: profile-likelihood confidence intervals for odds
   ratios. More accurate than Wald intervals, especially when
   sample size is modest or the outcome is rare.

   LACKFIT: runs Hosmer-Lemeshow goodness-of-fit test. Want
   p > 0.05, which means observed and predicted counts across
   risk deciles are not significantly different.

   Results (May 2026):
   N used = 3802 (438 dropped due to missing -- needs audit)
   AUC = 0.738
   H-L p = 0.1647 (good fit)
   Significant: age, male, cigsPerDay, sysBP, totChol, glucose
   Non-significant: BMI, heartRate
   Matches R output -- cross-language validation done.
   ------------------------------------------------------------ */
PROC LOGISTIC DATA=work.framingham_clean DESCENDING;
    CLASS male (REF='0') / PARAM=REF;
    MODEL TenYearCHD = age male cigsPerDay totChol sysBP BMI heartRate glucose
                       / SELECTION=NONE
                         CLODDS=PL
                         RISKLIMITS
                         LACKFIT;
    TITLE 'Framingham CHD -- Full Logistic Regression (diaBP removed, r=0.78 with sysBP)';
RUN;


/* ---- Step 6: Table 1 -- TLF-style output -------------------
   Standard submission Table 1: baseline characteristics by
   outcome group (TenYearCHD). Continuous variables reported
   as Mean (SD) with two-sample t-test p-values. Categorical
   variables reported as N (%) with Pearson chi-square p-values.

   Three-stage build:
   (a) Compute p-values via PROC TTEST and PROC FREQ with
       ODS OUTPUT to capture results as datasets.
   (b) Pre-aggregate all summary stats and format strings in
       PROC SQL into table1_cats, then merge p-values into
       table1_final.
   (c) PROC REPORT with ODS RTF renders the final submission
       table. All columns are DISPLAY -- no computation inside
       PROC REPORT itself.

   Key pattern: pre-aggregation in PROC SQL, not COMPUTE blocks.
   COMPUTE block string assembly inside PROC REPORT is unreliable
   across SAS versions. Pre-aggregation is the robust approach.
   ------------------------------------------------------------ */

/* (a) P-values -- continuous variables, two-sample t-test */
PROC TTEST DATA=work.framingham_clean;
    CLASS TenYearCHD;
    VAR age totChol sysBP;
    ODS OUTPUT TTests=pval_continuous;
RUN;

DATA pval_cont_clean;
    SET pval_continuous;
    WHERE Method='Pooled';
    p_cont = PUT(Probt, 6.4);
    KEEP Variable p_cont;
RUN;

/* (a) P-values -- categorical variables, Pearson chi-square */
PROC FREQ DATA=work.framingham_clean;
    TABLES TenYearCHD*male          / CHISQ NOPRINT;
    TABLES TenYearCHD*currentSmoker / CHISQ NOPRINT;
    ODS OUTPUT ChiSq=pval_categorical;
RUN;

DATA pval_cat_clean;
    SET pval_categorical;
    WHERE Statistic='Chi-Square';
    p_cat    = PUT(Prob, 6.4);
    Variable = SCAN(Table, -1, ' ');
    KEEP Variable p_cat;
RUN;

/* (b) Pre-aggregate summary stats with formatted strings.
   STRIP(PUT(...)) builds character strings cleanly.
   Mean (SD) for continuous, N (%) for categorical.
   All formatting resolved here -- PROC REPORT just displays. */
PROC SQL;
    CREATE TABLE table1_cats AS
    SELECT
        TenYearCHD,
        COUNT(*) AS n,
        STRIP(PUT(MEAN(age),     8.1)) || ' (' ||
            STRIP(PUT(STD(age),  8.1)) || ')' AS age_mean     LENGTH=15,
        STRIP(PUT(MEAN(totChol),    8.1)) || ' (' ||
            STRIP(PUT(STD(totChol), 8.1)) || ')' AS totChol_mean LENGTH=15,
        STRIP(PUT(MEAN(sysBP),    8.1)) || ' (' ||
            STRIP(PUT(STD(sysBP), 8.1)) || ')' AS sysBP_mean   LENGTH=15,
        STRIP(PUT(SUM(male), 8.)) || ' (' ||
            STRIP(PUT(MEAN(male)*100, 5.1)) || '%)' AS male_pct LENGTH=15,
        STRIP(PUT(SUM(currentSmoker), 8.)) || ' (' ||
            STRIP(PUT(MEAN(currentSmoker)*100, 5.1)) || '%)' AS smoker_pct LENGTH=15
    FROM work.framingham_clean
    GROUP BY TenYearCHD;
QUIT;

/* (b) Merge p-values onto summary table.
   P-values shown only on first row (TenYearCHD=0) per
   submission convention. <0.0001 formatted explicitly. */
PROC SQL;
    CREATE TABLE table1_final AS
    SELECT
        t.TenYearCHD,
        t.n,
        t.age_mean,
        t.totChol_mean,
        t.sysBP_mean,
        t.male_pct,
        t.smoker_pct,
        CASE WHEN t.TenYearCHD=0 THEN
            (SELECT CASE WHEN INPUT(p_cont,8.) < 0.0001 THEN '<0.0001'
                         ELSE p_cont END
             FROM pval_cont_clean WHERE Variable='age')
        ELSE '' END AS p_age LENGTH=8,
        CASE WHEN t.TenYearCHD=0 THEN
            (SELECT CASE WHEN INPUT(p_cont,8.) < 0.0001 THEN '<0.0001'
                         ELSE p_cont END
             FROM pval_cont_clean WHERE Variable='totChol')
        ELSE '' END AS p_totChol LENGTH=8,
        CASE WHEN t.TenYearCHD=0 THEN
            (SELECT CASE WHEN INPUT(p_cont,8.) < 0.0001 THEN '<0.0001'
                         ELSE p_cont END
             FROM pval_cont_clean WHERE Variable='sysBP')
        ELSE '' END AS p_sysBP LENGTH=8,
        CASE WHEN t.TenYearCHD=0 THEN
            (SELECT CASE WHEN INPUT(p_cat,8.) < 0.0001 THEN '<0.0001'
                         ELSE p_cat END
             FROM pval_cat_clean WHERE Variable='male')
        ELSE '' END AS p_male LENGTH=8,
        CASE WHEN t.TenYearCHD=0 THEN
            (SELECT CASE WHEN INPUT(p_cat,8.) < 0.0001 THEN '<0.0001'
                         ELSE p_cat END
             FROM pval_cat_clean WHERE Variable='currentSmoker')
        ELSE '' END AS p_smoker LENGTH=8
    FROM table1_cats t;
QUIT;

/* (c) Render final submission table to RTF */
ODS RTF FILE="/home/u64518804/framingham_table1.rtf" STYLE=Journal;

PROC REPORT DATA=table1_final NOWD SPLIT='|';
    COLUMN TenYearCHD n
           ('Continuous Variables -- Mean (SD)' age_mean p_age
            totChol_mean p_totChol sysBP_mean p_sysBP)
           ('Categorical Variables -- N (%)' male_pct p_male
            smoker_pct p_smoker);
    DEFINE TenYearCHD   / GROUP   'CHD|Status';
    DEFINE n            / DISPLAY 'N';
    DEFINE age_mean     / DISPLAY 'Age|(years)|Mean (SD)';
    DEFINE p_age        / DISPLAY 'p-value';
    DEFINE totChol_mean / DISPLAY 'Total|Cholesterol|(mg/dL)|Mean (SD)';
    DEFINE p_totChol    / DISPLAY 'p-value';
    DEFINE sysBP_mean   / DISPLAY 'Systolic BP|(mmHg)|Mean (SD)';
    DEFINE p_sysBP      / DISPLAY 'p-value';
    DEFINE male_pct     / DISPLAY 'Male|N (%)';
    DEFINE p_male       / DISPLAY 'p-value';
    DEFINE smoker_pct   / DISPLAY 'Current|Smoker|N (%)';
    DEFINE p_smoker     / DISPLAY 'p-value';
    TITLE1 'Table 1. Baseline Characteristics by 10-Year CHD Status';
    TITLE2 'Framingham Heart Study | Rohit Kambala | May 2026';
    FOOTNOTE1 'CHD = Coronary Heart Disease. Continuous: Mean (SD), two-sample t-test. Categorical: N (%), Pearson chi-square.';
    FOOTNOTE2 'Current smoking status was not significantly associated with 10-year CHD risk in this sample (p=0.21).';
RUN;

ODS RTF CLOSE;
