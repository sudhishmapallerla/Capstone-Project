CREATE DATABASE superstore_db;
USE superstore_db;

CREATE TABLE IF NOT EXISTS superstore (
    row_id INT PRIMARY KEY,
    order_id VARCHAR(50),
    order_date DATE,
    ship_date DATE,
    ship_mode VARCHAR(50),
    customer_id VARCHAR(50),
    customer_name VARCHAR(250),
    segment VARCHAR(50),
    country VARCHAR(100),
    city VARCHAR(100),
    state VARCHAR(100),
    postal_code VARCHAR(20),
    region VARCHAR(50),
    product_id VARCHAR(100),
    category VARCHAR(100),
    sub_category VARCHAR(100),
    product_name VARCHAR(255),
    sales DECIMAL(10, 4),
    quantity INT,
    discount DECIMAL(4, 2),
    profit DECIMAL(10, 4)
);

SET GLOBAL local_infile = 1;

LOAD DATA LOCAL INFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/Superstore_Inconsistent_Data csv.csv'
INTO TABLE superstore
FIELDS TERMINATED BY ',' 
ENCLOSED BY '"'
LINES TERMINATED BY '\r\n'
IGNORE 1 LINES
(
    row_id,
    order_id,
    @var_order_date,
    @var_ship_date,
    ship_mode,
    customer_id,
    customer_name,
    segment,
    country,
    city,
    state,
    postal_code,
    region,
    product_id,
    category,
    sub_category,
    product_name,
    sales,
    quantity,
    discount,
    profit
)
SET 
    order_date = CASE 
        WHEN @var_order_date IS NOT NULL AND TRIM(@var_order_date) != '' 
        THEN STR_TO_DATE(TRIM(@var_order_date), '%d-%m-%Y %H:%i')
        ELSE NULL 
    END,
    
    ship_date = CASE 
        WHEN @var_ship_date IS NOT NULL AND TRIM(@var_ship_date) != '' 
        THEN STR_TO_DATE(TRIM(@var_ship_date), '%d-%m-%Y %H:%i')
        ELSE NULL 
    END;

  SET GLOBAL local_infile = 1;
  
      SELECT row_id, order_id, order_date, ship_date 
FROM superstore 
WHERE order_date IS NOT NULL 
LIMIT 10;


SET SQL_SAFE_UPDATES = 0;
SET sql_mode = '';


DROP TABLE IF EXISTS superstore_clean;

CREATE TABLE superstore_clean AS
WITH Standardized AS (
    SELECT 
        CAST(`row_id` AS UNSIGNED) AS row_id,
        TRIM(`order_id`) AS order_id,
        
        -- Simply pass the dates directly (or cast to DATE)
        CAST(`order_date` AS DATE) AS order_date,
        CAST(`ship_date` AS DATE) AS ship_date,
        
        -- Standardize categorical casing & whitespace
        CASE LOWER(TRIM(`ship_mode`))
            WHEN 'standard class' THEN 'Standard Class'
            WHEN 'second class'   THEN 'Second Class'
            WHEN 'first class'    THEN 'First Class'
            WHEN 'same day'       THEN 'Same Day'
            ELSE TRIM(`ship_mode`)
        END AS ship_mode,
        
        TRIM(`customer_id`) AS customer_id,
        TRIM(`customer_name`) AS customer_name,
        
        CASE LOWER(TRIM(`segment`))
            WHEN 'consumer'    THEN 'Consumer'
            WHEN 'corporate'   THEN 'Corporate'
            WHEN 'home office' THEN 'Home Office'
            ELSE TRIM(`segment`)
        END AS segment,
        
        TRIM(`country`) AS country,
        TRIM(`city`) AS city,
        TRIM(`state`) AS state,
        TRIM(`postal_code`) AS postal_code,
        
        CASE LOWER(TRIM(`region`))
            WHEN 'south'   THEN 'South'
            WHEN 'west'    THEN 'West'
            WHEN 'central' THEN 'Central'
            WHEN 'east'    THEN 'East'
            ELSE TRIM(`region`)
        END AS region,
        
        TRIM(`product_id`) AS product_id,
        
        CASE 
            WHEN LOWER(TRIM(`category`)) LIKE 'office suppl%' THEN 'Office Supplies'
            WHEN LOWER(TRIM(`category`)) = 'furniture' THEN 'Furniture'
            WHEN LOWER(TRIM(`category`)) = 'technology' THEN 'Technology'
            ELSE TRIM(`category`)
        END AS category,
        
        TRIM(`sub_category`) AS sub_category,
        TRIM(`product_name`) AS product_name,
        
        -- Clean numeric fields
        CAST(`sales` AS DECIMAL(10,2)) AS sales,
        ABS(CAST(`quantity` AS SIGNED)) AS quantity,
        
        CASE 
            WHEN `discount` < 0 THEN 0.00
            WHEN `discount` > 1 THEN 1.00
            WHEN `discount` IS NULL THEN 0.00
            ELSE CAST(`discount` AS DECIMAL(4,2))
        END AS discount,
        
        CAST(`profit` AS DECIMAL(10,2)) AS profit,
        ROW_NUMBER() OVER (PARTITION BY row_id ORDER BY row_id) AS rn
    FROM superstore
)
SELECT 
    row_id, order_id, order_date, ship_date, ship_mode,
    customer_id, customer_name, segment, country, city, state,
    postal_code, region, product_id, category, sub_category,
    product_name, sales, quantity, discount, profit
FROM Standardized
WHERE rn = 1;

ALTER TABLE superstore_clean ADD PRIMARY KEY (row_id);

SELECT * 
FROM superstore_clean 
LIMIT 10;

#---------------Check Total Rows and Duplicates---------------------

SELECT 
    COUNT(*) AS total_rows,
    COUNT(DISTINCT row_id) AS unique_row_ids,
    COUNT(*) - COUNT(DISTINCT row_id) AS duplicate_rows
FROM superstore_clean;

#--------------------Check for Unintended NULL Values across Columns---------------------

SELECT 
    SUM(CASE WHEN row_id IS NULL THEN 1 ELSE 0 END) AS null_row_ids,
    SUM(CASE WHEN order_id IS NULL THEN 1 ELSE 0 END) AS null_order_ids,
    SUM(CASE WHEN order_date IS NULL THEN 1 ELSE 0 END) AS null_order_dates,
    SUM(CASE WHEN ship_date IS NULL THEN 1 ELSE 0 END) AS null_ship_dates,
    SUM(CASE WHEN customer_id IS NULL THEN 1 ELSE 0 END) AS null_customer_ids,
    SUM(CASE WHEN customer_name IS NULL THEN 1 ELSE 0 END) AS null_customer_names,
    SUM(CASE WHEN category IS NULL THEN 1 ELSE 0 END) AS null_categories,
    SUM(CASE WHEN sales IS NULL THEN 1 ELSE 0 END) AS null_sales,
    SUM(CASE WHEN discount IS NULL THEN 1 ELSE 0 END) AS null_discounts
FROM superstore_clean;

SET SQL_SAFE_UPDATES = 0;

-- Fill NULL ship_dates based on the average shipping delay for each ship_mode
UPDATE superstore_clean sc
JOIN (
    SELECT 
        ship_mode, 
        ROUND(AVG(DATEDIFF(ship_date, order_date))) AS avg_shipping_days
    FROM superstore_clean
    WHERE ship_date IS NOT NULL AND ship_mode IS NOT NULL
    GROUP BY ship_mode
) AS mode_avg ON sc.ship_mode = mode_avg.ship_mode
SET sc.ship_date = DATE_ADD(sc.order_date, INTERVAL mode_avg.avg_shipping_days DAY)
WHERE sc.ship_date IS NULL;


UPDATE superstore_clean
SET ship_date = DATE_ADD(order_date, INTERVAL 4 DAY)
WHERE ship_date IS NULL;

SELECT 
    COUNT(*) AS total_rows,
    SUM(CASE WHEN ship_date IS NULL THEN 1 ELSE 0 END) AS remaining_null_ship_dates
FROM superstore_clean;

#-------------Verify Date Logic Integrity-----------------

SELECT 
    COUNT(*) AS invalid_date_sequences
FROM superstore_clean
WHERE ship_date < order_date;


SET SQL_SAFE_UPDATES = 0;

-- Recalculate invalid ship dates using shipping mode averages
UPDATE superstore_clean sc
JOIN (
    SELECT 
        ship_mode, 
        ROUND(AVG(DATEDIFF(ship_date, order_date))) AS avg_shipping_days
    FROM superstore_clean
    WHERE ship_date >= order_date
    GROUP BY ship_mode
) AS mode_avg ON sc.ship_mode = mode_avg.ship_mode
SET sc.ship_date = DATE_ADD(sc.order_date, INTERVAL mode_avg.avg_shipping_days DAY)
WHERE sc.ship_date < sc.order_date;


UPDATE superstore_clean
SET ship_date = DATE_ADD(order_date, INTERVAL 4 DAY)
WHERE ship_date < order_date;


SELECT 
    COUNT(*) AS invalid_date_sequences
FROM superstore_clean
WHERE ship_date < order_date;

#---------------------Validate Numerical Boundaries & Anomalies------------------------

SELECT 
    SUM(CASE WHEN quantity <= 0 THEN 1 ELSE 0 END) AS invalid_quantities,
    SUM(CASE WHEN discount < 0 OR discount > 1 THEN 1 ELSE 0 END) AS invalid_discounts,
    MIN(quantity) AS min_quantity,
    MAX(quantity) AS max_quantity,
    MIN(discount) AS min_discount,
    MAX(discount) AS max_discount,
    MIN(sales) AS min_sales
FROM superstore_clean;

#-------------Verify Categorical Casing & Whitespace Cleanup----------------

-- Check distinct Ship Modes
SELECT ship_mode, COUNT(*) FROM superstore_clean GROUP BY ship_mode;

-- Check distinct Categories
SELECT category, COUNT(*) FROM superstore_clean GROUP BY category;

-- Check distinct Regions
SELECT region, COUNT(*) FROM superstore_clean GROUP BY region;

-- Check distinct Segments
SELECT segment, COUNT(*) FROM superstore_clean GROUP BY segment;