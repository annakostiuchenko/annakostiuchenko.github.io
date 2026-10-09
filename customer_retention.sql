INSTALL excel;
LOAD excel;


CREATE TABLE raw (
    Invoice       VARCHAR,
    StockCode     VARCHAR,
    Description   VARCHAR,
    Quantity      INTEGER,
    InvoiceDate   TIMESTAMP,
    Price         DOUBLE,
    "Customer ID" DOUBLE,
    Country       VARCHAR
);

COPY raw FROM '/Users/anna/Downloads/online_retail_II.xlsx'
    (FORMAT xlsx, SHEET 'Year 2009-2010', HEADER true);

COPY raw FROM '/Users/anna/Downloads/online_retail_II.xlsx'
    (FORMAT xlsx, SHEET 'Year 2010-2011', HEADER true);

SELECT COUNT(*) FROM raw;

SELECT
    COUNT(*)                                                       AS total_rows,
    COUNT(*) FILTER (WHERE "Customer ID" IS NULL)                  AS no_customer,
    COUNT(*) FILTER (WHERE starts_with(Invoice, 'C'))              AS cancellations,
    COUNT(*) FILTER (WHERE Quantity <= 0)                          AS zero_or_negative_qty,
    COUNT(*) FILTER (WHERE Price <= 0)                             AS zero_or_negative_price,
    COUNT(*) - (SELECT COUNT(*) FROM (SELECT DISTINCT * FROM raw)) AS exact_duplicates
FROM raw;

CREATE TABLE sales AS
SELECT DISTINCT
    Invoice,
    StockCode,
    Description,
    Quantity,
    InvoiceDate,
    Price,
    "Customer ID" AS customer_id,
    Country,
    Quantity * Price AS revenue
FROM raw
WHERE "Customer ID" IS NOT NULL
  AND NOT starts_with(Invoice, 'C')
  AND Quantity > 0
  AND Price > 0;

SELECT COUNT(*) AS clean_rows,
       COUNT(DISTINCT customer_id) AS customers
FROM sales;

CREATE TABLE cohorts AS
WITH firsts AS (
    SELECT customer_id,
           date_trunc('month', MIN(InvoiceDate)) AS cohort_month
    FROM sales
    GROUP BY customer_id
),
activity AS (
    SELECT DISTINCT
           s.customer_id,
           f.cohort_month,
           date_diff('month', f.cohort_month, date_trunc('month', s.InvoiceDate)) AS month_number
    FROM sales s
    JOIN firsts f USING (customer_id)
)
SELECT cohort_month,
       month_number,
       COUNT(*) AS customers,
       COUNT(*) * 1.0
         / FIRST_VALUE(COUNT(*)) OVER (PARTITION BY cohort_month ORDER BY month_number) AS retention
FROM activity
GROUP BY cohort_month, month_number
ORDER BY cohort_month, month_number;

CREATE TABLE rfm AS
WITH ref AS (
    SELECT MAX(InvoiceDate) + INTERVAL 1 DAY AS ref_date FROM sales
),
base AS (
    SELECT customer_id,
           date_diff('day', MAX(InvoiceDate), (SELECT ref_date FROM ref)) AS recency_days,
           COUNT(DISTINCT Invoice) AS frequency,
           SUM(revenue) AS monetary
    FROM sales
    GROUP BY customer_id
),
scored AS (
    SELECT *,
           6 - NTILE(5) OVER (ORDER BY recency_days) AS r_score,
           NTILE(5) OVER (ORDER BY frequency) AS f_score,
           NTILE(5) OVER (ORDER BY monetary) AS m_score
    FROM base
)
SELECT *,
       CASE
           WHEN r_score >= 4 AND f_score >= 4 THEN 'Champions'
           WHEN r_score >= 3 AND f_score >= 3 THEN 'Loyal'
           WHEN r_score >= 4 AND f_score <= 2 THEN 'New or promising'
           WHEN r_score <= 2 AND f_score >= 3 THEN 'At risk'
           WHEN r_score <= 2 AND f_score <= 2 THEN 'Lost'
           ELSE 'Needs attention'
       END AS segment
FROM scored;

COPY cohorts TO '/Users/anna/Downloads/cohorts.csv' (HEADER);
COPY rfm TO '/Users/anna/Downloads/rfm.csv' (HEADER);
