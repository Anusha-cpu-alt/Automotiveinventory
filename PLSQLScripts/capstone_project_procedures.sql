-----procedure-1---------------
create or replace PROCEDURE check_reorder_levels AS
BEGIN
 FOR rec IN (
 SELECT product_id, location_id, current_stock, reorder_level
 FROM INVENTORY_MASTER
 WHERE current_stock <= reorder_level
 )
 LOOP
 DBMS_OUTPUT.PUT_LINE('Reorder needed for Product ' || rec.product_id ||
 ' at Location ' || rec.location_id);
 END LOOP;
EXCEPTION
 WHEN OTHERS THEN
 DBMS_OUTPUT.PUT_LINE('Error in check_reorder_levels: ' || SQLERRM);
END;


--------------------procedure-2-------------------------
create or replace PROCEDURE transfer_stock (
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
        'TRX-' || TO_CHAR(SYSDATE, 'YYYYMMDDHH24MISS'),
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
        'TRX-' || TO_CHAR(SYSDATE, 'YYYYMMDDHH24MISS') || 'R',
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
        'TRF-' || TO_CHAR(SYSDATE, 'YYYYMMDDHH24MISS'),
        p_product_id,
        p_from_location,
        p_to_location,
        p_quantity,
        SYSDATE,
        'COMPLETED',
        p_approved_by
    );

    COMMIT;
END;