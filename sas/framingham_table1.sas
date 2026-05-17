/* ============================================================
   Framingham CHD -- Table 1 and Logistic Regression
   Rohit Kambala | May 2026

   Dataset: framingham_fixed.csv (4240 obs, 16 vars)
   Goal: reproduce my R logistic regression in SAS and
   understand the output like a practitioner would.

   Key decisions documented here:
   - Six variables came in as character due to NA strings in CSV.
     All converted to numeric in one clean DATA step below.
   - diaBP kept in the model for now but flagged -- it's
     correlated with sysBP and its coefficient is unstable.
     PROC CORR below quantifies this before we decide to drop it.
   - 438 obs dropped by PROC LOGISTIC due to missing values.
     That's 10% of the dataset. Worth a proper missing data
     audit before this goes anywhere near a submission.
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
   call the whole column character. Can't change its mind later.

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
   ------------------------------------------------------------ */
PROC CORR DATA=work.framingham_clean NOSIMPLE;
    VAR sysBP diaBP;
    TITLE 'Correlation: sysBP vs diaBP -- checking multicollinearity';
RUN;


/* ---- Step 5: Logistic regression -- full model -------------
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

   Current results (May 2026):
   N used = 3802 (438 dropped due to missing -- needs audit)
   AUC = 0.738
   H-L p = 0.1647 (good fit)
   Significant: age, male, cigsPerDay, sysBP, totChol, glucose
   Non-significant: diaBP, BMI, heartRate
   Matches R output -- cross-language validation done.
   ------------------------------------------------------------ */
PROC LOGISTIC DATA=work.framingham_clean DESCENDING;
    CLASS male (REF='0') / PARAM=REF;
    MODEL TenYearCHD = age male cigsPerDay totChol sysBP diaBP BMI heartRate glucose
                       / SELECTION=NONE
                         CLODDS=PL
                         RISKLIMITS
                         LACKFIT;
    TITLE 'Framingham CHD -- Full Logistic Regression';
RUN;


/* ---- What to do next ---------------------------------------
   1. Review PROC CORR output above. If r(sysBP, diaBP) > 0.7,
      rerun the model dropping diaBP and compare AIC values.
   2. Run a proper missing data audit on the 438 dropped obs.
      Are missings random, or concentrated in sicker patients?
      If the latter, results may be biased.
   3. When ready to upgrade this to a TLF-style output,
      add ODS RTF and PROC REPORT around the key tables.
   ------------------------------------------------------------ */
