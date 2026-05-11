# Predicting 10-Year Coronary Heart Disease Risk Using Machine Learning

**Course:** GPH-GU 2338 — Machine Learning for Public Health, Spring 2026  
**Authors:** Rohit Kambala, Jacob Parquet  
**Institution:** NYU School of Global Public Health

## Overview
This project applies and compares four supervised machine learning classifiers 
to predict 10-year coronary heart disease (CHD) risk using the Framingham Heart 
Study dataset (n = 4,240). Logistic regression was the recommended model, 
achieving the highest sensitivity (0.828) and an AUC of 0.699 — statistically 
indistinguishable from Random Forest (DeLong test: p = 0.563).

## Models Compared
- Logistic Regression
- K-Nearest Neighbors (KNN)
- Random Forest
- XGBoost

## Key Findings
| Model | AUC | Sensitivity | Specificity |
|---|---|---|---|
| Logistic Regression (t=0.30) | 0.699 | 0.828 | 0.363 |
| Random Forest | 0.690 | 0.648 | 0.673 |
| XGBoost | 0.652 | 0.531 | 0.732 |
| KNN | 0.597 | 0.383 | 0.757 |

## Repository Structure
data/           # Framingham Heart Study dataset
report/         # R Markdown source and compiled PDF report

## Reproducing the Analysis
1. Clone this repository
2. Open `report/Framingham_CHD_Report_Final.Rmd` in RStudio
3. Ensure `framingham.csv` is in the same directory as the .Rmd file
4. Install required packages: `tidyverse`, `caret`, `pROC`, `corrplot`, 
   `smotefamily`, `randomForest`, `xgboost`, `rms`, `knitr`, `kableExtra`, `scales`
5. Knit to PDF

## Dataset
Framingham Heart Study dataset — publicly available on 
[Kaggle](https://www.kaggle.com/datasets/aasheesh200/framingham-heart-study-dataset)