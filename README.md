# Financial Risk & Fraud Detection Analysis


## Project Overview
**Skylar Trading Enterprises**, a fictional Fintech operating in major Indian hubs, is facing a rising fraud rate of **6.52%**. This project analyzes 7,500 synthetic digital transactions to transition the company's security strategy from *reactive* dispute resolution to *proactive* fraud prevention.

By leveraging **SQL for feature engineering** and **Tableau for visual analytics**, I developed a heuristic **Risk Scoring Engine** that flags high-probability threats based on behavioral anomalies, IP risk, and transaction patterns.

---

##  Business Problem
*   **The Issue:** Digital payment fraud is eroding trust and causing direct financial loss.
*   **The Data:** 7,500 rows covering UPI, NetBanking, Cards, and Wallet transactions.
*   **The Objective:** 
    1.  Identify specific "Hotspots" (Payment Mode + Transaction Type) susceptible to fraud.
    2.  Detect "Account Takeover" (ATO) patterns using behavioral indicators.
    3.  Assign a **Risk Probability Score (0-100)** to every transaction to prioritize analyst workload.

---

## Tech Stack & Methodology

### 1. Data Processing (Google BigQuery SQL)
*   **Data Validation:** Checked for nulls, duplicates, and negative values.
*   **Feature Engineering:**
    *   **Spending Deviation:** Calculated the ratio of *Current Transaction* vs. *User Average* to detect anomalies.
    *   **Heuristic Risk Scoring:** Created a weighted scoring model (0-100) based on:
        *   `IP Risk Score > 0.9` (+30 pts)
        *   `Deviation Ratio > 2.0` (+25 pts)
        *   `International Transaction` (+20 pts)
        *   `New Account (<30 Days)` (+15 pts)
        *   `Suspicious Hours (20:00-04:00)` (+10 pts)

### 2. Visualization (Tableau)
*   **Dashboarding:** Built a "Command Center" dashboard with dynamic parameters.
*   **Interactivity:** Created a "Risk Threshold" slider allowing analysts to filter transactions based on probability scores (e.g., "Show only scores > 80").

---

## 📊 Key Insights & Findings

### 1. The "Account Takeover" (ATO) Vulnerability
Contrary to the expectation that *New Accounts* are riskiest, the analysis revealed that **Mature Accounts (>90 Days)** are responsible for the highest volume of high-risk transactions. This strongly suggests **Account Takeover** scenarios where trusted users are compromised.

### 2. The Danger Zone: UPI Withdrawals
A heatmap analysis identified the intersection of **UPI** and **Withdrawals** as the highest concentration of fraud. Fraudsters prefer this channel due to immediate settlement and irreversibility.

### 3. High-Value Outliers
The "Medium Risk" category (defined by IP Risk + Amount Deviation) accounted for the largest total financial loss, proving that focusing solely on "Critical" alerts misses significant revenue leakage.

---

## Dashboard Preview

*(Replace this text with a screenshot of your Tableau Dashboard)*

[**🔗 Click Here to View the Interactive Tableau Dashboard**](INSERT_YOUR_TABLEAU_PUBLIC_LINK_HERE)

---

## SQL Logic Snippet
*The following SQL snippet demonstrates the logic used to generate the Probability Score:*

```sql
SELECT 
  transaction_id,
  -- Risk Level Categorization
  CASE
    WHEN is_international = 1 AND ip_risk_score > 0.9 AND account_age_days < 30 THEN 'Critical Risk'
    WHEN is_international = 1 AND ip_risk_score > 0.9 THEN 'High Risk'
    ELSE 'Standard'
  END AS risk_level,

  -- Probability Score Calculation (0-100)
  LEAST(100, 
    (
      IF(is_international = 1, 20, 0) + 
      IF(ip_risk_score > 0.9, 30, 0) + 
      IF(account_age_days < 30, 15, 0) + 
      IF(transaction_hour >= 20 OR transaction_hour <= 4, 10, 0) +
      IF(deviation_ratio > 2.0, 25, 0)
    )
  ) AS fraud_probability_score
FROM transformed_fraud_data;
