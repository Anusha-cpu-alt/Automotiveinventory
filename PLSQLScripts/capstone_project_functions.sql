SET SERVEROUTPUT ON


-----------FUNCTION1-----------------------------
CREATE OR REPLACE FUNCTION calculate_stock_value (
   p_product_id   IN  VARCHAR2,
   p_location_id  IN  VARCHAR2
)
RETURN NUMBER
IS
   v_stock_value    NUMBER(14,2);
BEGIN
   -- Calculate stock value = current_stock * unit_cost
   SELECT current_stock * unit_cost
   INTO v_stock_value
   FROM INVENTORY_MASTER
   WHERE product_id = p_product_id
     AND location_id = p_location_id;

   RETURN v_stock_value;

-- Handle NO DATA FOUND
EXCEPTION
   WHEN NO_DATA_FOUND THEN
      DBMS_OUTPUT.put_line('ERROR: No inventory record exists for the given product and location.');
      RETURN 0;

   WHEN TOO_MANY_ROWS THEN
      DBMS_OUTPUT.put_line('ERROR: More than one inventory record found. Please check data integrity.');
      RETURN NULL;

   WHEN OTHERS THEN
      DBMS_OUTPUT.put_line('ERROR: ' || SQLERRM || ' -- Please contact admin or check input.');
      RETURN NULL;
END calculate_stock_value;
/
-------------------------------------------------------------------
--calling calculate_stock_value

DECLARE
   result NUMBER;
BEGIN
   result := calculate_stock_value('CAB-002', 'USA-018');
   DBMS_OUTPUT.put_line('Stock Value = ' || result);
END;
-----------------------------------------------------------------


-----------------------------------------------------
-------FUNCTION-2--------------------------

CREATE OR REPLACE FUNCTION supplier_perf_rating (
   p_supplier_id IN SUPPLIERS.supplier_id%TYPE
)
RETURN NUMBER
IS
   v_avg_rating NUMBER(4,2);
   v_category   VARCHAR2(20);
BEGIN
   SELECT ROUND(AVG(quality_rating), 1)
   INTO v_avg_rating
   FROM SUPPLIER_PERFORMANCE
   WHERE supplier_id = p_supplier_id;

   IF v_avg_rating IS NULL THEN
      DBMS_OUTPUT.put_line('INFO: No performance data found for supplier ID ' || p_supplier_id || '.');
      RETURN 0;
   END IF;

   IF v_avg_rating >= 4 THEN
      v_category := 'High';
   ELSIF v_avg_rating >= 2.5 THEN
      v_category := 'Medium';
   ELSE
      v_category := 'Low';
   END IF;

   DBMS_OUTPUT.put_line('Supplier Average Rating: ' || v_avg_rating || ' (' || v_category || ')');

   RETURN v_avg_rating;

EXCEPTION
   WHEN NO_DATA_FOUND THEN
      DBMS_OUTPUT.put_line('INFO: No performance data found for supplier ID ' || p_supplier_id || '.');
      RETURN 0;

   WHEN OTHERS THEN
      DBMS_OUTPUT.put_line('ERROR: ' || SQLERRM || ' -- Please verify supplier ID or data.');
      RETURN NULL;
END supplier_perf_rating;
---------------------------------------------
--calling supplier_perf_rating

SET SERVEROUTPUT ON;
DECLARE
   r NUMBER;
BEGIN
   r := supplier_perf_rating('SUP-004');
END;
/













SELECT username, password, spare4
FROM dba_users
WHERE username = 'AUTOTECH_INVENTORY';






