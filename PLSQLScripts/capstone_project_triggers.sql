----CREATE SEQUENCE-------------
CREATE SEQUENCE audit_seq START WITH 1 INCREMENT BY 1;

---------TRIGGER1: "Trigger to log all inventory changes"
CREATE OR REPLACE TRIGGER trg_inventory_audit
AFTER INSERT OR UPDATE OR DELETE ON INVENTORY_MASTER
FOR EACH ROW
DECLARE
v_old_values CLOB;
v_new_values CLOB;
v_operation_type VARCHAR2(10);
v_audit_id VARCHAR2(20);
v_changed_by VARCHAR2(50);
v_change_date DATE := SYSDATE;
BEGIN
-- Determine the operation type
IF INSERTING THEN
v_operation_type := 'INSERT';
v_old_values := NULL;  -- No old values for insert
v_new_values := 'Product ID: ' || :NEW.product_id ||
                ', Location ID: ' || :NEW.location_id ||
                ', Current Stock: ' || :NEW.current_stock ||
                ', Reorder Level: ' || :NEW.reorder_level ||
                ', Max Stock Level: ' || :NEW.max_stock_level ||
                ', Safety Stock: ' || :NEW.safety_stock ||
                ', Last Movement: ' || TO_CHAR(:NEW.last_movement, 'YYYY-MM-DD HH24:MI:SS') ||
                ', Unit Cost: ' || :NEW.unit_cost;
ELSIF UPDATING THEN
    v_operation_type := 'UPDATE';
    v_old_values := 'Product ID: ' || :OLD.product_id ||
                    ', Location ID: ' || :OLD.location_id ||
                    ', Current Stock: ' || :OLD.current_stock ||
                    ', Reorder Level: ' || :OLD.reorder_level ||
                    ', Max Stock Level: ' || :OLD.max_stock_level ||
                    ', Safety Stock: ' || :OLD.safety_stock ||
                    ', Last Movement: ' || TO_CHAR(:OLD.last_movement, 'YYYY-MM-DD HH24:MI:SS') ||
                    ', Unit Cost: ' || :OLD.unit_cost;
    v_new_values := 'Product ID: ' || :NEW.product_id ||
                    ', Location ID: ' || :NEW.location_id ||
                     ', Current Stock: ' || :NEW.current_stock ||
                     ', Reorder Level: ' || :NEW.reorder_level ||
                     ', Max Stock Level: ' || :NEW.max_stock_level ||
                     ', Safety Stock: ' || :NEW.safety_stock ||
                     ', Last Movement: ' || TO_CHAR(:NEW.last_movement, 'YYYY-MM-DD HH24:MI:SS') ||
                     ', Unit Cost: ' || :NEW.unit_cost;
ELSIF DELETING THEN
    v_operation_type := 'DELETE';
    v_old_values := 'Product ID: ' || :OLD.product_id ||
                    ', Location ID: ' || :OLD.location_id ||
                    ', Current Stock: ' || :OLD.current_stock ||
                    ', Reorder Level: ' || :OLD.reorder_level ||
                    ', Max Stock Level: ' || :OLD.max_stock_level ||
                    ', Safety Stock: ' || :OLD.safety_stock ||
                    ', Last Movement: ' || TO_CHAR(:OLD.last_movement, 'YYYY-MM-DD HH24:MI:SS') ||
                    ', Unit Cost: ' || :OLD.unit_cost;
    v_new_values := NULL;  -- No new values for delete
END IF;



v_changed_by := NVL(USER, 'SYSTEM');
SELECT 'AUD' || LPAD(TO_CHAR(audit_seq.NEXTVAL), 17, '0') INTO v_audit_id FROM DUAL;
-- Insert into AUDIT_TRAIL
INSERT INTO AUDIT_TRAIL ( audit_id,
                          table_name,
                          operation_type,
                          old_values,
                          new_values,
                          changed_by,
                          change_date) 
      VALUES (
                v_audit_id,
                'INVENTORY_MASTER',
                v_operation_type,
                v_old_values,
                v_new_values,
                v_changed_by,
                v_change_date
            );
EXCEPTION
  WHEN NO_DATA_FOUND THEN
    RAISE_APPLICATION_ERROR(-20001, 'Audit sequence not found or initialization error.');
  WHEN VALUE_ERROR THEN
    RAISE_APPLICATION_ERROR(-20002, 'Value error in audit logging: Check data lengths.');
  WHEN DUP_VAL_ON_INDEX THEN
    RAISE_APPLICATION_ERROR(-20003, 'Duplicate audit ID detected.');
  WHEN OTHERS THEN
    RAISE_APPLICATION_ERROR(-20000, 'Unexpected error in inventory audit trigger: ' || SQLERRM);
END;
--------------------------------------------------------------------
-- Inserting sample data
 INSERT INTO INVENTORY_MASTER (inventory_id, product_id, location_id, current_stock, reorder_level, max_stock_level, safety_stock, last_movement, unit_cost)
 VALUES ('INV-501', 'MIR-179', 'USA-050', 1500, 500, 5000, 200, SYSDATE, 45.50);
-- Performing a change
  UPDATE INVENTORY_MASTER
  SET current_stock = 1400, last_movement = SYSDATE
  WHERE inventory_id = 'INV-0372';
-- 5.AUDIT_TRAIL to verify:
 SELECT * FROM AUDIT_TRAIL
 ORDER BY change_date DESC;
 
 ---------------------------------------------------------------------------------
 ---TRIGGER-2 "Trigger to update last movement date"----------------------------

 CREATE OR REPLACE TRIGGER trg_update_last_movement
BEFORE INSERT OR UPDATE OF current_stock ON INVENTORY_MASTER
FOR EACH ROW
WHEN (NEW.current_stock IS NOT NULL)
BEGIN
-- Setting last_movement to SYSDATE if not provided
IF INSERTING THEN
IF :NEW.last_movement IS NULL THEN
:NEW.last_movement := SYSDATE;
END IF;
--Setting last_movement to SYSDATE if current_stock changed
ELSIF UPDATING AND (:OLD.current_stock <> :NEW.current_stock OR :OLD.current_stock IS NULL OR :NEW.current_stock IS NULL) THEN
   :NEW.last_movement := SYSDATE;
END IF;
 EXCEPTION
  WHEN VALUE_ERROR THEN
    RAISE_APPLICATION_ERROR(-20004, 'Value error in last movement update: Check data types and values.');
WHEN OTHERS THEN
    RAISE_APPLICATION_ERROR(-20005, 'Unexpected error in last movement update trigger: ' || SQLERRM);
END;
---------------------------------------------------------------------

------------------------------------------------------------------------
--TESTING TRIGGER-2-------------
--INERTING WITHOUT LAST MOVEMENT
INSERT INTO INVENTORY_MASTER (inventory_id, product_id, location_id, current_stock, reorder_level, max_stock_level, safety_stock, unit_cost)
VALUES ('INV-0501', 'CAB-017', 'BRA-038', 1000, 300, 3000, 100, 52.30);
-----------------------------------------
---UPDATING 
 UPDATE INVENTORY_MASTER
  SET current_stock = 2400
  WHERE inventory_id = 'INV-0501';
  
---VERIFYING THE LAST MOVEMENT
SELECT inventory_id, current_stock, TO_CHAR(last_movement, 'YYYY-MM-DD HH24:MI:SS') AS last_movement
FROM INVENTORY_MASTER
WHERE inventory_id = 'INV-0501';

------------------------------------------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------

---TRIGGER-3 "Trigger to validate stock quantities"------------------------------
CREATE OR REPLACE TRIGGER trg_validate_stock_quantities
BEFORE INSERT OR UPDATE ON INVENTORY_MASTER
FOR EACH ROW
BEGIN
IF :NEW.current_stock < 0 THEN
    RAISE_APPLICATION_ERROR(-20006, 'Current stock cannot be negative.');
END IF;
IF :NEW.reorder_level < 0 THEN
   RAISE_APPLICATION_ERROR(-20007, 'Reorder level cannot be negative.');
END IF;
IF :NEW.max_stock_level < 0 THEN
   RAISE_APPLICATION_ERROR(-20008, 'Maximum stock level cannot be negative.');
END IF;
IF :NEW.safety_stock < 0 THEN
   RAISE_APPLICATION_ERROR(-20009, 'Safety stock cannot be negative.');
END IF;

IF :NEW.safety_stock > :NEW.reorder_level THEN
    RAISE_APPLICATION_ERROR(-20010, 'Safety stock cannot exceed reorder level.');
END IF;
IF :NEW.reorder_level >= :NEW.max_stock_level THEN
    RAISE_APPLICATION_ERROR(-20011, 'Reorder level must be less than maximum stock level.');
END IF;
IF :NEW.current_stock > :NEW.max_stock_level THEN
    RAISE_APPLICATION_ERROR(-20012, 'Current stock cannot exceed maximum stock level.');
END IF;
IF :NEW.current_stock < :NEW.safety_stock THEN
    RAISE_APPLICATION_ERROR(-20013, 'Current stock cannot be below safety stock level.');
END IF;
EXCEPTION
   WHEN VALUE_ERROR THEN
         RAISE_APPLICATION_ERROR(-20014, 'Value error in stock quantity validation: Check data types and values.');
   WHEN OTHERS THEN
         RAISE_APPLICATION_ERROR(-20015, 'Unexpected error in stock quantity validation trigger: ' || SQLERRM);
END;
------------------------------------------------------
-----TESTING TRIGGER-3
---INSERTING
INSERT INTO INVENTORY_MASTER (inventory_id, product_id, location_id, current_stock, reorder_level, max_stock_level, safety_stock, last_movement, unit_cost)
VALUES ('INV-0502', 'ELE-095', 'USA-018', 6000, 500, 5000, 200, SYSDATE, 125.00);

---UPDATING
UPDATE INVENTORY_MASTER
SET current_stock = 200
WHERE inventory_id = 'INV-0372';






