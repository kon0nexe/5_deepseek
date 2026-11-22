-- =====================================================================
-- Триггеры контроля согласованности и автоматического заполнения дат.
-- =====================================================================
WHENEVER SQLERROR EXIT SQL.SQLCODE

CREATE OR REPLACE TRIGGER trg_dim_match_biu
BEFORE INSERT OR UPDATE OF match_date, time_id ON dim_match
FOR EACH ROW
DECLARE
    l_full_date DATE;
BEGIN
    SELECT full_date INTO l_full_date
      FROM dim_time
     WHERE time_id = :NEW.time_id;
    IF TRUNC(l_full_date) <> TRUNC(:NEW.match_date) THEN
        RAISE_APPLICATION_ERROR(-20001,
            'Дата матча должна совпадать с датой календарного измерения DIM_TIME');
    END IF;
END;
/

CREATE OR REPLACE TRIGGER trg_tickets_biu
BEFORE INSERT OR UPDATE ON tickets
FOR EACH ROW
DECLARE
    l_match_stadium  NUMBER;
    l_sector_stadium NUMBER;
BEGIN
    IF INSERTING THEN
        :NEW.created_at := COALESCE(:NEW.created_at, SYSTIMESTAMP);
        :NEW.updated_at := SYSTIMESTAMP;
    ELSE
        :NEW.created_at := :OLD.created_at;
        :NEW.updated_at := SYSTIMESTAMP;

        IF UPDATING('STATUS') AND :NEW.status <> :OLD.status THEN
            IF NOT (
                (:OLD.status = 'FREE'     AND :NEW.status IN ('RESERVED','SOLD')) OR
                (:OLD.status = 'RESERVED' AND :NEW.status IN ('FREE','SOLD')) OR
                (:OLD.status = 'SOLD'     AND :NEW.status = 'RETURNED') OR
                (:OLD.status = 'RETURNED' AND :NEW.status IN ('RESERVED','SOLD'))
            ) THEN
                RAISE_APPLICATION_ERROR(-20002,
                    'Недопустимый переход статуса билета');
            END IF;
        END IF;
    END IF;

    -- Сектор должен принадлежать тому же стадиону, на котором проводится матч.
    SELECT m.stadium_id, s.stadium_id
      INTO l_match_stadium, l_sector_stadium
      FROM dim_match m CROSS JOIN dim_sector s
     WHERE m.match_id = :NEW.match_id
       AND s.sector_id = :NEW.sector_id;

    IF l_match_stadium <> l_sector_stadium THEN
        RAISE_APPLICATION_ERROR(-20003,
            'Выбранный сектор не относится к стадиону указанного матча');
    END IF;
END;
/

PROMPT Триггеры TRG_DIM_MATCH_BIU и TRG_TICKETS_BIU созданы.
