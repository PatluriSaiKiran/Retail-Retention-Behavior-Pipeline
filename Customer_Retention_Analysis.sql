-- 1. Creating a table named public.raw_Retail_Analysis 
CREATE TABLE public.raw_retail_analysis (
    invoice_no   TEXT,
    stock_code   TEXT,
    description  TEXT,
    quantity     TEXT,
    invoice_date TEXT,
    unit_price   TEXT,
    customer_id  TEXT,
    country      TEXT
	);
	
--2. load data using the safe public folder 
COPY public.raw_retail_analysis
FROM 'C:\Users\Public\online_retail_II.csv'
WITH (FORMAT csv, HEADER true, DELIMITER ',', QUOTE '"', ENCODING 'WIN1252');

--3. Verify if the data loaded perfectly,
select * from public.raw_retail_analysis;

-- 4. Correcting and changing data types with explicit type casting
ALTER TABLE public.raw_retail_analysis 
    ALTER COLUMN quantity TYPE INTEGER 
        USING quantity::INTEGER,
        
    ALTER COLUMN unit_price TYPE NUMERIC 
        USING unit_price::NUMERIC,
        
    ALTER COLUMN invoice_date TYPE TIMESTAMP 
        USING invoice_date::TIMESTAMP;

-- 5. Top-selling products by quantity
select description, sum(quantity) as total_quantity from public.raw_retail_analysis
group by description 
order by total_quantity desc
limit 10;

-- 6. Recency, Frequency, and Monetary (RFM) Analysis 
WITH raw_metrics AS (
    -- Step 1: Calculate raw RFM metrics
    SELECT 
        customer_id, 
        EXTRACT(DAY FROM '2011-12-10'::timestamp - MAX(invoice_date)) AS recency,
        COUNT(DISTINCT invoice_no) AS total_orders, 
        SUM(quantity * unit_price) AS total_spend 
    FROM public.raw_retail_analysis 
    WHERE invoice_no NOT LIKE 'C%' 
      AND customer_id IS NOT NULL 
      AND customer_id != '' 
    GROUP BY customer_id  
),
rfm_scores AS (
    -- Step 2: Score them 1 to 5 using NTILE
    SELECT 
        customer_id,
        recency,
        total_orders,
        total_spend,
        NTILE(5) OVER (ORDER BY recency DESC) AS r_score, -- Higher recency days = lower score
        NTILE(5) OVER (ORDER BY total_orders ASC) AS f_score,
        NTILE(5) OVER (ORDER BY total_spend ASC) AS m_score
    FROM raw_metrics
)
-- Step 3: Assign Business Segments based on Scores
SELECT 
    customer_id,
    r_score, f_score, m_score,
    (r_score::text || f_score::text || m_score::text) AS rfm_cell,
    total_spend,
    CASE 
        WHEN r_score >= 4 AND f_score >= 4 THEN 'Champions'
        WHEN r_score >= 3 AND f_score >= 3 THEN 'Loyal Customers'
        WHEN r_score >= 4 AND f_score = 1 THEN 'Recent New Customers'
        WHEN r_score >= 3 AND f_score = 2 THEN 'Potential Loyalists'
        WHEN r_score = 2 AND f_score >= 3 THEN 'At Risk / Don''t Lose Them'
        WHEN r_score = 1 AND f_score >= 4 THEN 'Can''t Lose Them (Sleeping Giants)'
        WHEN r_score = 2 AND f_score <= 2 THEN 'About to Sleep'
        WHEN r_score = 1 AND f_score <= 2 THEN 'Lost / Hibernating'
        ELSE 'About to Sleep' 
    END AS customer_segment
FROM rfm_scores
ORDER BY total_spend DESC;

-- 7. Cohort Retention Analysis (Run separately)
WITH customer_cohort AS (
    -- Step 1: Find the first purchase month ("Birth Month") for each customer
    SELECT 
        customer_id, 
        DATE_TRUNC('month', MIN(invoice_date)) AS cohort_month
    FROM public.raw_retail_analysis 
    WHERE invoice_no NOT LIKE 'C%' 
      AND customer_id IS NOT NULL 
      AND customer_id != ''
    GROUP BY customer_id
),
customer_activity AS (
    -- Step 2: Find all unique months where a customer made a purchase
    SELECT DISTINCT 
        customer_id, 
        DATE_TRUNC('month', invoice_date) AS purchase_month
    FROM public.raw_retail_analysis
    WHERE invoice_no NOT LIKE 'C%' 
      AND customer_id IS NOT NULL 
      AND customer_id != ''
),
cohort_intervals AS (
    -- Step 3: Join and calculate the Month Index gap (0 = same month, 1 = next month, etc.)
    SELECT 
        ca.customer_id,
        cc.cohort_month,
        ca.purchase_month,
        (EXTRACT(YEAR FROM ca.purchase_month) - EXTRACT(YEAR FROM cc.cohort_month)) * 12 +
        (EXTRACT(MONTH FROM ca.purchase_month) - EXTRACT(MONTH FROM cc.cohort_month)) AS cohort_index
    FROM customer_activity ca
    JOIN customer_cohort cc ON ca.customer_id = cc.customer_id
),
cohort_size AS (
    -- Step 4: Calculate the total base size of each starting cohort month
    SELECT 
        cohort_month, 
        COUNT(DISTINCT customer_id) AS total_customers
    FROM cohort_intervals
    WHERE cohort_index = 0
    GROUP BY cohort_month
)
-- Step 5: Final Matrix output showing retention over intervals
SELECT 
    i.cohort_month,
    s.total_customers AS cohort_base_size,
    i.cohort_index,
    COUNT(DISTINCT i.customer_id) AS active_customers,
    ROUND((COUNT(DISTINCT i.customer_id)::numeric / s.total_customers) * 100, 2) AS retention_percentage
FROM cohort_intervals i
JOIN cohort_size s ON i.cohort_month = s.cohort_month
GROUP BY i.cohort_month, s.total_customers, i.cohort_index
ORDER BY i.cohort_month, i.cohort_index;

















