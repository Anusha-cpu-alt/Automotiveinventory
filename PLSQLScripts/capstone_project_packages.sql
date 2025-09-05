---PACKAGE-1---------
SET SERVEROUTPUT ON
--------------SPECIFICATION------------------
CREATE OR REPLACE PACKAGE inventory_pkg AS
    -- Procedure to check which products are below reorder level
    PROCEDURE check_reorder_level;

    -- Procedure to transfer stock between locations
    PROCEDURE transfer_stock(
        p_product_id    IN VARCHAR2,
        p_from_location IN VARCHAR2,
        p_to_location   IN VARCHAR2,
        p_quantity      IN NUMBER,
        p_approved_by   IN VARCHAR2
    );
END inventory_pkg;
/

---------BODY---------------
CREATE OR REPLACE PACKAGE BODY inventory_pkg AS

    ----------------------------------------------------------------------
    -- Procedure 1: Check products below reorder level
    ----------------------------------------------------------------------
    PROCEDURE check_reorder_level IS
    BEGIN
        FOR rec IN (
            SELECT im.product_id,
                   p.product_name,
                   im.location_id,
                   im.current_stock,
                   im.reorder_level
            FROM inventory_master im
            JOIN products p ON im.product_id = p.product_id
            WHERE im.current_stock <= im.reorder_level
        ) LOOP
    
            DBMS_OUTPUT.PUT_LINE(
                'ALERT: Product ' || rec.product_id || ' (' || rec.product_name || 
                ') at Location ' || rec.location_id ||
                ' stock=' || rec.current_stock ||
                ', reorder level=' || rec.reorder_level
            );
        END LOOP;
    END check_reorder_level;


    ----------------------------------------------------------------------
    -- Procedure 2: Transfer stock between locations
    ----------------------------------------------------------------------
    PROCEDURE transfer_stock(
        p_product_id    IN VARCHAR2,
        p_from_location IN VARCHAR2,
        p_to_location   IN VARCHAR2,
        p_quantity      IN NUMBER,
        p_approved_by   IN VARCHAR2
    ) IS
        v_from_stock NUMBER;
    BEGIN
        -- 1. Check stock at source
        SELECT current_stock
        INTO   v_from_stock
        FROM   inventory_master
        WHERE  product_id  = p_product_id
        AND    location_id = p_from_location
        FOR UPDATE;

        IF v_from_stock < p_quantity THEN
            RAISE_APPLICATION_ERROR(-20001, 'Insufficient stock at source location.');
        END IF;

        -- 2. Deduct stock from source
        UPDATE inventory_master
        SET    current_stock = current_stock - p_quantity,
               last_movement = SYSDATE
        WHERE  product_id  = p_product_id
        AND    location_id = p_from_location;

        -- 3. Add stock to destination
        UPDATE inventory_master
        SET    current_stock = current_stock + p_quantity,
               last_movement = SYSDATE
        WHERE  product_id  = p_product_id
        AND    location_id = p_to_location;

        -- 4. Record transaction in INVENTORY_TRANSACTIONS (issue)
        INSERT INTO inventory_transactions (
            transaction_id, product_id, location_id,
            transaction_type, quantity, unit_cost, trans_date, reference_no, created_by
        ) VALUES (
            'TRX-' || TO_CHAR(SYSDATE, 'YYYYMMDDHH24MISS') || LPAD(DBMS_RANDOM.VALUE(1,99),2,'0'),
            p_product_id,
            p_from_location,
            'TRANSFER',
            -p_quantity,
            NULL,
            SYSDATE,
            'STOCK_TRANSFER',
            p_approved_by
        );

        -- 5. Record transaction in INVENTORY_TRANSACTIONS (receipt)
        INSERT INTO inventory_transactions (
            transaction_id, product_id, location_id,
            transaction_type, quantity, unit_cost, trans_date, reference_no, created_by
        ) VALUES (
            'TRF-' || TO_CHAR(SYSDATE, 'YYYYMMDDHH24MISS') || LPAD(DBMS_RANDOM.VALUE(1,99),2,'0'),

            p_product_id,
            p_to_location,
            'TRANSFER',
            p_quantity,
            NULL,
            SYSDATE,
            'STOCK_TRANSFER',
            p_approved_by
        );

        -- 6. Insert into STOCK_TRANSFERS
        INSERT INTO stock_transfers (
            transfer_id, product_id, from_location, to_location, quantity,
            transfer_date, status, approved_by
        ) VALUES (
            'TRX-' || TO_CHAR(SYSDATE, 'YYYYMMDDHH24MISS') || LPAD(DBMS_RANDOM.VALUE(1,99),2,'0'),
            p_product_id,
            p_from_location,
            p_to_location,
            p_quantity,
            SYSDATE,
            'COMPLETED',
            p_approved_by
        );

        COMMIT;
    END transfer_stock;

END inventory_pkg;

--------
SET SERVEROUTPUT ON;
------------
--run reorder check
BEGIN
    inventory_pkg.check_reorder_level;
END;
--------------
BEGIN
    inventory_pkg.transfer_stock(
        p_product_id    => 'MIR-196',
        p_from_location => 'UK-040',
        p_to_location   => 'USA-050',
        p_quantity      => 100,
        p_approved_by   => 'Admin'
    );
END;
-------
--check the transfered stocks
select * from stock_transfers;
select * from inventory_master;
SELECT *
FROM inventory_transactions
ORDER BY trans_date DESC;









------------------------------------------------------------------------------
--PACKAGE-2-----
CREATE SEQUENCE perf_id_seq 
START WITH 1 
INCREMENT BY 1 
NOCACHE 
NOCYCLE;

CREATE SEQUENCE po_line_seq 
  START WITH 1 
  INCREMENT BY 1 
  NOCACHE 
  NOCYCLE;



--SPECIFICATION
CREATE OR REPLACE PACKAGE supplier_pkg AS

    PROCEDURE add_supplier(
        p_supplier_id    IN VARCHAR2,
        p_supplier_name  IN VARCHAR2,
        p_country        IN VARCHAR2,
        p_supplier_type  IN VARCHAR2,
        p_quality_rating IN NUMBER,
        p_lead_time_days IN NUMBER,
        p_payment_terms  IN VARCHAR2,
        p_certification  IN VARCHAR2
    );

    PROCEDURE create_purchase_order(
        p_po_number    IN VARCHAR2,
        p_supplier_id  IN VARCHAR2,
        p_order_date   IN DATE,
        p_expected_date IN DATE,
        p_created_by   IN VARCHAR2,
        p_products     IN SYS.ODCIVARCHAR2LIST,
        p_quantities   IN SYS.ODCINUMBERLIST,
        p_unit_prices  IN SYS.ODCINUMBERLIST
    );

    PROCEDURE update_po_status(
        p_po_number   IN VARCHAR2,
        p_new_status  IN VARCHAR2,
        p_actual_date IN DATE
    );

    PROCEDURE record_supplier_performance(
        p_supplier_id    IN VARCHAR2,
        p_po_number      IN VARCHAR2,
        p_delivery_date  IN DATE,
        p_promised_date  IN DATE,
        p_quality_rating IN NUMBER,
        p_qty_delivered  IN NUMBER,
        p_qty_rejected   IN NUMBER,
        p_perf_month     IN VARCHAR2
    );

END supplier_pkg;
/







---BODY--
CREATE OR REPLACE PACKAGE BODY supplier_pkg AS

    --------------------------------------------------------------------
    PROCEDURE add_supplier(
        p_supplier_id    IN VARCHAR2,
        p_supplier_name  IN VARCHAR2,
        p_country        IN VARCHAR2,
        p_supplier_type  IN VARCHAR2,
        p_quality_rating IN NUMBER,
        p_lead_time_days IN NUMBER,
        p_payment_terms  IN VARCHAR2,
        p_certification  IN VARCHAR2
    ) IS
    BEGIN
        INSERT INTO suppliers (
            supplier_id, supplier_name, country, supplier_type,
            quality_rating, lead_time_days, payment_terms,
            certification
        ) VALUES (
            p_supplier_id, p_supplier_name, p_country, p_supplier_type,
            p_quality_rating, p_lead_time_days, p_payment_terms,
            p_certification
        );
        COMMIT;
    END add_supplier;
    --------------------------------------------------------------------

    --------------------------------------------------------------------
    PROCEDURE create_purchase_order(
        p_po_number    IN VARCHAR2,
        p_supplier_id  IN VARCHAR2,
        p_order_date   IN DATE,
        p_expected_date IN DATE,
        p_created_by   IN VARCHAR2,
        p_products     IN SYS.ODCIVARCHAR2LIST,
        p_quantities   IN SYS.ODCINUMBERLIST,
        p_unit_prices  IN SYS.ODCINUMBERLIST
    ) IS
        v_total_amount NUMBER := 0;
    BEGIN
        INSERT INTO purchase_orders (
            po_number, supplier_id, order_date,
            expected_date, total_amount,
            order_status, created_by
        ) VALUES (
            p_po_number, p_supplier_id, p_order_date,
            p_expected_date, 0,
            'PENDING', p_created_by
        );

      FOR i IN 1 .. p_products.COUNT LOOP
    INSERT INTO po_line_items (
        line_id, po_number, product_id,
        quantity, unit_price, line_total
    ) VALUES (
        'LINE-' || po_line_seq.NEXTVAL,  -- instead of using timestamp
        p_po_number,
        p_products(i),
        p_quantities(i),
        p_unit_prices(i),
        p_quantities(i) * p_unit_prices(i)
    );

    v_total_amount := v_total_amount + (p_quantities(i) * p_unit_prices(i));
END LOOP;


        UPDATE purchase_orders
        SET total_amount = v_total_amount
        WHERE po_number = p_po_number;

        COMMIT;
    END create_purchase_order;
    --------------------------------------------------------------------

    --------------------------------------------------------------------
    PROCEDURE update_po_status(
        p_po_number   IN VARCHAR2,
        p_new_status  IN VARCHAR2,
        p_actual_date IN DATE
    ) IS
    BEGIN
        UPDATE purchase_orders
        SET order_status = p_new_status,
            actual_date  = p_actual_date
        WHERE po_number = p_po_number;

        IF SQL%ROWCOUNT = 0 THEN
            RAISE_APPLICATION_ERROR(-20020, 'PO not found.');
        END IF;

        COMMIT;
    END update_po_status;
    --------------------------------------------------------------------

    --------------------------------------------------------------------
    PROCEDURE record_supplier_performance(
        p_supplier_id    IN VARCHAR2,
        p_po_number      IN VARCHAR2,
        p_delivery_date  IN DATE,
        p_promised_date  IN DATE,
        p_quality_rating IN NUMBER,
        p_qty_delivered  IN NUMBER,
        p_qty_rejected   IN NUMBER,
        p_perf_month     IN VARCHAR2
    ) IS
        v_perf_id VARCHAR2(30);
    BEGIN
        v_perf_id := 'PERF-' || TO_CHAR(SYSDATE, 'YYYYMMDDHH24MISS') || perf_id_seq.NEXTVAL;

        INSERT INTO supplier_performance (
            performance_id, supplier_id, po_number,
            delivery_date, promised_date,
            quality_rating, qty_delivered, qty_rejected,
            performance_month
        ) VALUES (
            v_perf_id, p_supplier_id, p_po_number,
            p_delivery_date, p_promised_date,
            p_quality_rating, p_qty_delivered, p_qty_rejected,
            p_perf_month
        );

        COMMIT;
    END record_supplier_performance;
    --------------------------------------------------------------------

END supplier_pkg;
/


-------------------------------------------------------
---calling add_supplier
BEGIN
    supplier_pkg.add_supplier(
        p_supplier_id    => 'SUP-031',
        p_supplier_name  => 'Japan Supplier 31',
        p_country        => 'Japan',
        p_supplier_type  => 'OEM',
        p_quality_rating => 4.5,
        p_lead_time_days => 10,
        p_payment_terms  => '45 days',
        p_certification  => 'ISO9101'
    );
END;
------------------------
--calling create purchase order
DECLARE
    v_products    SYS.ODCIVARCHAR2LIST := SYS.ODCIVARCHAR2LIST('ELE-091', 'ELE-092');
    v_quantities  SYS.ODCINUMBERLIST   := SYS.ODCINUMBERLIST(50, 60);
    v_unit_prices SYS.ODCINUMBERLIST   := SYS.ODCINUMBERLIST(50.00, 75.00);
BEGIN
    supplier_pkg.create_purchase_order(
        p_po_number     => 'PO-2024-122',
        p_supplier_id   => 'SUP-023',
        p_order_date    => SYSDATE,
        p_expected_date => SYSDATE + 7,
        p_created_by    => 'AdminUser',
        p_products      => v_products,
        p_quantities    => v_quantities,
        p_unit_prices   => v_unit_prices
    );
END;
/
------------------------------------------------
/*SELECT * 
FROM purchase_orders 
WHERE po_number = 'PO-2024-122'; */

-------------------------------------------------------------------
--calling updtae_po_status
BEGIN
    supplier_pkg.update_po_status(
        p_po_number   => 'PO-2024-122',
        p_new_status  => 'DELIVERED',
        p_actual_date => SYSDATE
    );
END;
/

/*SELECT po_number,
       order_status,
       actual_date
FROM   purchase_orders
WHERE  po_number = 'PO-2024-122';
 */
-------------------------------------------------------
--calling record supplier performance
BEGIN
    supplier_pkg.record_supplier_performance(
        p_supplier_id    => 'SUP-023',
        p_po_number      => 'PO-2024-121',
        p_delivery_date  => SYSDATE,
        p_promised_date  => SYSDATE - 2,
        p_quality_rating => 4.7,
        p_qty_delivered  => 300,
        p_qty_rejected   => 5,
        p_perf_month     => '2025-08'
    );
END;
/
/*SELECT *
FROM supplier_performance
ORDER BY delivery_date DESC;*/
-------------------------------------------

