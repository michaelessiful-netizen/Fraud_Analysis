--Data Validation
--checking for duplications and invalid entries
select
count(*) as total_rows,
count(distinct transaction_id) as unique_transaction_id,
count(distinct user_id) as unique_user_id,
countif(transaction_amount <= 0) as invalid_amounts,
countif(transaction_hour not between 0 and 23) as invalid_hours
from
projectspractice0.fraud_detection.digital_fraud_dataset; -- Retuned perfectly, there are no existing errors in the dataset

-- Data Transformation
-- creating a duplicate to transfrom the data
CREATE OR REPLACE TABLE projectspractice0.fraud_detection.digital_fraud_dataset_transformed AS
SELECT
*,
IF(fraud_label = 1, 'Fraud', 'Legitimate') AS status_label,
IF(is_international = 1, 'International', 'Domestic') AS status_scope,
from
projectspractice0.fraud_detection.digital_fraud_dataset;

-- Data Analysis
-- a. identifying outlier that don't typically fit a customer's transaction average
SELECT
transaction_id,
user_id,
transaction_amount,
avg_transaction_amount,
SAFE_DIVIDE(transaction_amount, avg_transaction_amount) AS deviation_ratio,
FROM projectspractice0.fraud_detection.digital_fraud_dataset;

-- b. Identifying Outliers
SELECT
transaction_id,
user_id,
transaction_amount,
avg_transaction_amount,
ip_risk_score,
-- c. Logic for the outlier flag
CASE
WHEN SAFE_DIVIDE(transaction_amount, avg_transaction_amount) > 2.0
AND ip_risk_score > 0.6 THEN 'High-Risk Outlier'
WHEN SAFE_DIVIDE(transaction_amount, avg_transaction_amount) > 2.0 THEN 'Amount Outlier'
WHEN ip_risk_score > 0.6 THEN 'IP Risk Outlier'
ELSE 'Standard'
END AS outlier_category
FROM projectspractice0.fraud_detection.digital_fraud_dataset;

-- d. Creating a new table to add new columns (Deviation Ratio and Ip Risk)
CREATE OR REPLACE TABLE `projectspractice0.fraud_detection.final_fraud_analysis` AS
SELECT
  *,
  -- the Deviation Ratio
  SAFE_DIVIDE(transaction_amount, avg_transaction_amount) AS deviation_ratio,
  
  -- the Outlier Category Logic (If amount is 2x average AND IP risk is high)
  CASE 
    WHEN SAFE_DIVIDE(transaction_amount, avg_transaction_amount) > 2.0 
         AND ip_risk_score > 0.6 THEN 'High-Risk Outlier'
    -- If only amount is 2x average
    WHEN SAFE_DIVIDE(transaction_amount, avg_transaction_amount) > 2.0 THEN 'Amount Outlier'
    -- If only IP risk is high
    WHEN ip_risk_score > 0.6 THEN 'IP Risk Outlier'
    -- Otherwise
    ELSE 'Standard'
  END AS outlier_category
FROM 
  `projectspractice0.fraud_detection.digital_fraud_dataset_transformed`;

CREATE OR REPLACE TABLE `projectspractice0.fraud_detection.fraud_scored_final` AS
SELECT
  *,
  -- e. Creating a risk level column
  -- 1. Create Risk Level (Categorical)
  CASE
    -- Critical: Meets ALL the criteria you specified
    WHEN is_international = 1 
         AND ip_risk_score > 0.6 
         AND account_age_days < 30  -- Assuming < 30 days is a "New Account"
         AND transaction_hour >= 20 THEN 'Critical Risk'
    
    -- High: High IP Risk + International (regardless of time/age)
    WHEN is_international = 1 AND ip_risk_score > 0.6 THEN 'High Risk'
    
    -- Medium: Just one major red flag
    WHEN ip_risk_score > 0.6 OR deviation_ratio > 3.0 THEN 'Medium Risk'
    
    -- Low: Everything else
    ELSE 'Low Risk'
  END AS risk_level,

  -- Create Probability Score (0-100 Scale)
  -- I sum up points for risk factors, then use LEAST to ensure it never goes above 100
  -- P Risk: 30 points (Usually the strongest indicator).
  -- Explanaation
  -- Spending Deviation: 25 points.
  --International: 20 points.
  --New Account: 15 points.
  --Late Hours: 10 points.
  
  LEAST(100, 
    (
      -- Base points for International
      IF(is_international = 1, 20, 0) + 
      
      -- Points for High IP Risk (Heavy weighting)
      IF(ip_risk_score > 0.9, 30, 0) + 
      
      -- Points for New Account
      IF(account_age_days < 30, 15, 0) + 
      
      -- Points for Suspicious Hours
      IF(transaction_hour >= 20 OR transaction_hour <= 4, 10, 0) +
      
      -- Points for Money Deviation (spending way more than average)
      IF(deviation_ratio > 2.0, 25, 0)
    )
  ) AS fraud_probability_score

FROM `projectspractice0.fraud_detection.final_fraud_analysis1`;

SELECT
  *
FROM
  `projectspractice0.fraud_detection.fraud_scored_final`;

-- Data Analysis for Visualization and answering Business questions
-- a. Identifying High_risk fraud Hotspots
SELECT
  payment_mode,
  transaction_type,
  COUNT(*) AS total_fraud_cases,
  ROUND((SUM(fraud_label) / COUNT(*)) * 100, 2) as fraud_rate_percentage,
  AVG(CASE WHEN fraud_label = 1 THEN ip_risk_score END) as avg_ip_risk_fraud,
  AVG(CASE WHEN fraud_label = 0 THEN ip_risk_score END) as avg_ip_risk_legit
FROM `projectspractice0.fraud_detection.fraud_scored_final`
GROUP BY 1, 2
ORDER BY fraud_rate_percentage DESC;

-- b. Behavior indicators
SELECT 
  login_attempts_last_24h,
  transaction_hour,
  COUNT(*) as total_volume,
  SUM(fraud_label) as fraud_volume,
  ROUND((SUM(fraud_label) / COUNT(*)) * 100, 2) as fraud_rate_percentage
FROM `projectspractice0.fraud_detection.fraud_scored_final`
GROUP BY 1, 2
ORDER BY login_attempts_last_24h DESC, transaction_hour;

-- c. New Account vs.International Risk Profiling
SELECT 
  IF(is_international = 1, 'International', 'Domestic') as scope,
  CASE 
    WHEN account_age_days < 30 THEN 'New Account (<30 Days)'
    WHEN account_age_days BETWEEN 30 AND 90 THEN 'Established (30-90 Days)'
    ELSE 'Mature (>90 Days)'
  END as account_maturity,
  AVG(fraud_probability_score) as avg_fraud_score,
  SUM(transaction_amount) as total_money_moved,
  SUM(CASE WHEN fraud_label = 1 THEN transaction_amount ELSE 0 END) as total_fraud_loss
FROM `projectspractice0.fraud_detection.fraud_scored_final`
GROUP BY 1, 2
ORDER BY total_fraud_loss DESC;

-- d. Fraud Funnel - Value at Risk by Outlier Category
-- This helps executives understand where the money is going based on the outlier categories created
SELECT 
  outlier_category,
  risk_level,
  COUNT(transaction_id) as count_of_transactions,
  SUM(transaction_amount) as total_transaction_value,
  SUM(CASE WHEN fraud_label = 1 THEN transaction_amount ELSE 0 END) as actual_fraud_loss
FROM `projectspractice0.fraud_detection.fraud_scored_final`
GROUP BY 1, 2
ORDER BY actual_fraud_loss DESC;