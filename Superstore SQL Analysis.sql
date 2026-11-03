Use superstore_db;

#--------------Step 1. Check your cleaned dataset--------------------

SELECT COUNT(*) AS total_rows
FROM superstore_clean;

SELECT *
FROM superstore_clean
LIMIT 10;

SELECT
    MIN(order_date) AS first_order_date,
    MAX(order_date) AS last_order_date,
    COUNT(DISTINCT order_id) AS distinct_orders,
    COUNT(DISTINCT customer_id) AS distinct_customers,
    SUM(sales) AS total_sales,
    SUM(profit) AS total_profit
FROM superstore_clean;


#-------------Step 2. Aggregate functions — overall business performance---------------
#---------Overall KPI analysis--------------------

SELECT
    ROUND(SUM(sales), 2) AS total_sales,
    ROUND(SUM(profit), 2) AS total_profit,
    ROUND(AVG(sales), 2) AS average_line_sales,
    SUM(quantity) AS total_quantity,
    ROUND(AVG(discount), 2) AS average_discount,
    COUNT(*) AS total_order_lines,
    COUNT(DISTINCT order_id) AS total_orders,
    COUNT(DISTINCT customer_id) AS total_customers,
    ROUND(
        100.0 * SUM(profit) / NULLIF(SUM(sales), 0), 2
    ) AS profit_margin_pct
FROM superstore_clean;


#------------Sales and profit by category------------------------
SELECT
    category,
    COUNT(*) AS order_lines,
    COUNT(DISTINCT order_id) AS orders,
    SUM(quantity) AS units_sold,
    ROUND(SUM(sales), 2) AS total_sales,
    ROUND(SUM(profit), 2) AS total_profit,
    ROUND(AVG(discount), 2) AS avg_discount,
    ROUND(
        100.0 * SUM(profit) / NULLIF(SUM(sales), 0), 2
    ) AS profit_margin_pct
FROM superstore_clean
GROUP BY category
ORDER BY total_sales DESC;

#-----------Regional performance---------------------

SELECT
    region,
    COUNT(DISTINCT order_id) AS total_orders,
    SUM(quantity) AS total_quantity,
    ROUND(SUM(sales), 2) AS total_sales,
    ROUND(SUM(profit), 2) AS total_profit,
    ROUND(AVG(discount), 2) AS average_discount
FROM superstore_clean
GROUP BY region
ORDER BY total_profit DESC;

#--------------Step 3. UDFs — create reusable business calculations----------

#---------Function to calculate profit margin-------------------

DELIMITER $$

CREATE FUNCTION fn_profit_margin(
    p_sales DECIMAL(10,2),
    p_profit DECIMAL(10,2)
)
RETURNS DECIMAL(10,2)
DETERMINISTIC
NO SQL
BEGIN
    RETURN CASE
        WHEN p_sales IS NULL OR p_sales = 0 THEN NULL
        WHEN p_profit IS NULL THEN NULL
        ELSE ROUND((p_profit / p_sales) * 100, 2)
    END;
END$$

DELIMITER ;

#----------Test the function:--------------
SELECT
    order_id,
    product_name,
    sales,
    profit,
    fn_profit_margin(sales, profit) AS profit_margin_pct
FROM superstore_clean
LIMIT 20;

#----------Function to classify profit performance----------

#This example uses simple, illustrative thresholds: negative profit is Loss, profit margin below 10% is Low Margin, and the rest is Healthy Margin.
DELIMITER $$

CREATE FUNCTION fn_profit_status(
    p_sales DECIMAL(10,2),
    p_profit DECIMAL(10,2)
)
RETURNS VARCHAR(20)
DETERMINISTIC
NO SQL
BEGIN
    RETURN CASE
        WHEN p_sales IS NULL OR p_profit IS NULL
            THEN 'Unknown'
        WHEN p_profit < 0
            THEN 'Loss'
        WHEN p_sales = 0
            THEN 'Zero Sales'
        WHEN (p_profit / p_sales) * 100 < 10
            THEN 'Low Margin'
        ELSE 'Healthy Margin'
    END;
END$$

DELIMITER ;

#----Analyze the results:


SELECT
    fn_profit_status(sales, profit) AS profit_status,
    COUNT(*) AS order_lines,
    ROUND(SUM(sales), 2) AS total_sales,
    ROUND(SUM(profit), 2) AS total_profit
FROM superstore_clean
GROUP BY fn_profit_status(sales, profit)
ORDER BY total_profit;

#--------------Step 4. JOINs — combine related datasets-----------------
#JOINs are useful when you want to analyze data from multiple tables. Your current SQL file defines a single cleaned fact-like table, so we'll create a few simple dimension tables from it.

#-----Create a customer dimension----
CREATE TABLE IF NOT EXISTS dim_customer AS
SELECT DISTINCT
    customer_id,
    customer_name,
    segment
FROM superstore_clean
WHERE customer_id IS NOT NULL;

ALTER TABLE dim_customer
ADD INDEX idx_dim_customer_id (customer_id);

#----------Create a product dimension---------

CREATE TABLE IF NOT EXISTS dim_product AS
SELECT DISTINCT
    product_id,
    product_name,
    category,
    sub_category
FROM superstore_clean
WHERE product_id IS NOT NULL;

ALTER TABLE dim_product
ADD INDEX idx_dim_product_id (product_id);

#-----------INNER JOIN — customer sales
#--------Returns matching customers only.

SELECT
    c.customer_id,
    c.customer_name,
    c.segment,
    COUNT(DISTINCT s.order_id) AS total_orders,
    ROUND(SUM(s.sales), 2) AS total_sales,
    ROUND(SUM(s.profit), 2) AS total_profit
FROM superstore_clean s
INNER JOIN dim_customer c
    ON s.customer_id = c.customer_id
GROUP BY
    c.customer_id,
    c.customer_name,
    c.segment
ORDER BY total_sales DESC
LIMIT 20;

#----------LEFT JOIN — find missing customer matches--------------

SELECT
    s.row_id,
    s.order_id,
    s.customer_id,
    s.customer_name,
    s.sales
FROM superstore_clean s
LEFT JOIN dim_customer c
    ON s.customer_id = c.customer_id
WHERE c.customer_id IS NULL;

#-------JOIN — product profitability----------------
SELECT
    p.category,
    p.sub_category,
    p.product_id,
    p.product_name,
    ROUND(SUM(s.sales), 2) AS total_sales,
    ROUND(SUM(s.profit), 2) AS total_profit,
    SUM(s.quantity) AS units_sold
FROM superstore_clean s
INNER JOIN dim_product p
    ON s.product_id = p.product_id
GROUP BY
    p.category,
    p.sub_category,
    p.product_id,
    p.product_name
ORDER BY total_profit DESC
LIMIT 20;

#-----------Window functions — advanced analysis---------------------
#------------Rank products by total sales-----------------
WITH product_sales AS (
    SELECT
        product_id,
        product_name,
        category,
        SUM(sales) AS total_sales,
        SUM(profit) AS total_profit
    FROM superstore_clean
    GROUP BY product_id, product_name, category
)
SELECT
    product_id,
    product_name,
    category,
    ROUND(total_sales, 2) AS total_sales,
    ROUND(total_profit, 2) AS total_profit,
    RANK() OVER (
        ORDER BY total_sales DESC
    ) AS sales_rank
FROM product_sales
ORDER BY sales_rank;

#RANK() assigns the same rank to ties and skips subsequent rank numbers.
#Use DENSE_RANK() if you don't want gaps in the ranking.

#-------Rank products within each category---------------
WITH product_sales AS (
    SELECT
        category,
        product_id,
        product_name,
        SUM(sales) AS total_sales
    FROM superstore_clean
    GROUP BY category, product_id, product_name
)
SELECT
    category,
    product_name,
    ROUND(total_sales, 2) AS total_sales,
    DENSE_RANK() OVER (
        PARTITION BY category
        ORDER BY total_sales DESC
    ) AS category_rank
FROM product_sales
ORDER BY category, category_rank;

#PARTITION BY category restarts the ranking for each category.

#-----------Running monthly sales total--------------------
WITH monthly_sales AS (
    SELECT
        DATE_FORMAT(order_date, '%Y-%m-01') AS month_start,
        SUM(sales) AS total_sales
    FROM superstore_clean
    WHERE order_date IS NOT NULL
    GROUP BY DATE_FORMAT(order_date, '%Y-%m-01')
)
SELECT
    month_start,
    ROUND(total_sales, 2) AS monthly_sales,
    ROUND(
        SUM(total_sales) OVER (
            ORDER BY month_start
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ), 2
    ) AS running_sales
FROM monthly_sales
ORDER BY month_start;

#This gives you monthly sales and cumulative sales up to each month.

#-------------Compare monthly sales with the previous month-------------------

WITH monthly_sales AS (
    SELECT
        DATE_FORMAT(order_date, '%Y-%m-01') AS month_start,
        SUM(sales) AS total_sales
    FROM superstore_clean
    WHERE order_date IS NOT NULL
    GROUP BY DATE_FORMAT(order_date, '%Y-%m-01')
),
sales_comparison AS (
    SELECT
        month_start,
        total_sales,
        LAG(total_sales) OVER (
            ORDER BY month_start
        ) AS previous_month_sales
    FROM monthly_sales
)
SELECT
    month_start,
    ROUND(total_sales, 2) AS current_sales,
    ROUND(previous_month_sales, 2) AS previous_sales,
    ROUND(total_sales - previous_month_sales, 2) AS sales_change,
    ROUND(
        100.0 * (total_sales - previous_month_sales)
        / NULLIF(previous_month_sales, 0), 2
    ) AS growth_pct
FROM sales_comparison
ORDER BY month_start;

#---------Stored procedures — reusable reports------------------
#Stored procedures let you run predefined SQL logic by passing parameters.

#-----Procedure for a date-range sales report---------
DELIMITER $$

CREATE PROCEDURE sp_sales_report(
    IN p_start_date DATE,
    IN p_end_date DATE
)
BEGIN
    IF p_start_date IS NULL
       OR p_end_date IS NULL
       OR p_start_date > p_end_date THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Invalid date range';
    END IF;

    SELECT
        category,
        region,
        COUNT(DISTINCT order_id) AS total_orders,
        SUM(quantity) AS total_quantity,
        ROUND(SUM(sales), 2) AS total_sales,
        ROUND(SUM(profit), 2) AS total_profit,
        ROUND(
            100.0 * SUM(profit) / NULLIF(SUM(sales), 0), 2
        ) AS profit_margin_pct
    FROM superstore_clean
    WHERE order_date >= p_start_date
      AND order_date < DATE_ADD(p_end_date, INTERVAL 1 DAY)
    GROUP BY category, region
    ORDER BY total_sales DESC;
END$$

DELIMITER ;

#-----------Execute the procedure:--------------------
CALL sp_sales_report('2015-01-01', '2015-12-31');

#Replace the dates with the period you want to analyze. The example uses a year as a parameter illustration, not a claim about the actual date range in your loaded data.
#----------Procedure for a customer performance report----------------
DELIMITER $$

CREATE PROCEDURE sp_top_customers(
    IN p_limit INT
)
BEGIN
    IF p_limit IS NULL OR p_limit < 1 OR p_limit > 1000 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Limit must be between 1 and 1000';
    END IF;

    SELECT
        customer_id,
        customer_name,
        segment,
        COUNT(DISTINCT order_id) AS total_orders,
        ROUND(SUM(sales), 2) AS total_sales,
        ROUND(SUM(profit), 2) AS total_profit
    FROM superstore_clean
    GROUP BY customer_id, customer_name, segment
    ORDER BY total_sales DESC
    LIMIT p_limit;
END$$

DELIMITER ;

#Execute it:

CALL sp_top_customers(10);
#This returns the top 10 customers by total sales

#-----Procedure for regional profitability-------
DELIMITER $$

CREATE PROCEDURE sp_region_profitability()
BEGIN
    SELECT
        region,
        COUNT(DISTINCT order_id) AS total_orders,
        ROUND(SUM(sales), 2) AS total_sales,
        ROUND(SUM(profit), 2) AS total_profit,
        ROUND(
            100.0 * SUM(profit) / NULLIF(SUM(sales), 0), 2
        ) AS profit_margin_pct
    FROM superstore_clean
    GROUP BY region
    ORDER BY total_profit DESC;
END$$

DELIMITER ;

CALL sp_region_profitability();

#To see the procedures created:

SHOW PROCEDURE STATUS
WHERE Db = 'superstore_db';

#------Triggers — validate data and audit changes--------------
#A trigger runs automatically when a specified table event occurs. For this project,
# we'll demonstrate data validation on a separate table and audit changes to it.

#Why use a separate table? Your existing superstore_clean table is a cleaned analysis table.
# We should avoid introducing triggers that unexpectedly interfere with your cleaning process 
# or existing historical records.


#Create a table for future sales records
CREATE TABLE IF NOT EXISTS superstore_sales_entry (
    row_id INT PRIMARY KEY,
    order_id VARCHAR(50),
    order_date DATE,
    ship_date DATE,
    sales DECIMAL(10,2),
    quantity INT,
    discount DECIMAL(4,2),
    profit DECIMAL(10,2)
);


#-----Create a BEFORE INSERT validation trigger-----
#This trigger rejects invalid sales entries.

DELIMITER $$

CREATE TRIGGER trg_validate_sales_insert
BEFORE INSERT ON superstore_sales_entry
FOR EACH ROW
BEGIN
    IF NEW.sales IS NULL OR NEW.sales < 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Sales must be non-negative';
    END IF;

    IF NEW.quantity IS NULL OR NEW.quantity <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Quantity must be greater than zero';
    END IF;

    IF NEW.discount IS NULL
       OR NEW.discount < 0
       OR NEW.discount > 1 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Discount must be between 0 and 1';
    END IF;

    IF NEW.order_date IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Order date is required';
    END IF;

    IF NEW.ship_date IS NOT NULL
       AND NEW.ship_date < NEW.order_date THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Ship date cannot precede order date';
    END IF;
END$$

DELIMITER ;


#Test with a valid record:
INSERT INTO superstore_sales_entry
    (row_id, order_id, order_date, ship_date,
     sales, quantity, discount, profit)
VALUES
    (1, 'TEST-001', '2026-01-10', '2026-01-12',
     250.00, 2, 0.10, 35.00);
     
#Test an invalid discount:

INSERT INTO superstore_sales_entry
    (row_id, order_id, order_date, sales, quantity, discount, profit)
VALUES
    (2, 'TEST-002', '2026-01-10', 250.00, 2, 1.50, 35.00);
    
#-------Create an audit log table---------------
#An audit table records changes made to sales and profit values.

CREATE TABLE IF NOT EXISTS sales_audit_log (
    audit_id BIGINT AUTO_INCREMENT PRIMARY KEY,
    row_id INT NOT NULL,
    old_sales DECIMAL(10,2),
    new_sales DECIMAL(10,2),
    old_profit DECIMAL(10,2),
    new_profit DECIMAL(10,2),
    changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);


#-----Create an AFTER UPDATE trigger--------------

DELIMITER $$

CREATE TRIGGER trg_audit_sales_update
AFTER UPDATE ON superstore_sales_entry
FOR EACH ROW
BEGIN
    IF NOT (OLD.sales <=> NEW.sales)
       OR NOT (OLD.profit <=> NEW.profit) THEN

        INSERT INTO sales_audit_log (
            row_id,
            old_sales,
            new_sales,
            old_profit,
            new_profit
        )
        VALUES (
            NEW.row_id,
            OLD.sales,
            NEW.sales,
            OLD.profit,
            NEW.profit
        );
    END IF;
END$$

DELIMITER ;

#Test the trigger:

UPDATE superstore_sales_entry
SET sales = 275.00,
    profit = 40.00
WHERE row_id = 1;

SELECT *
FROM sales_audit_log
ORDER BY audit_id DESC;

#You should see the original and updated values recorded in the audit table.






