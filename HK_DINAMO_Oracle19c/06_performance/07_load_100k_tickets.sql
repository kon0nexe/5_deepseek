-- =====================================================================
-- Загрузка минимум 100 000 тестовых строк в TICKETS.
-- Выполнять от HK_DINAMO после seed_demo_data.sql.
-- Десять тестовых матчей, по 10 000 мест на матч (2 сектора по 5 000).
-- =====================================================================
WHENEVER SQLERROR EXIT SQL.SQLCODE
SET SERVEROUTPUT ON

DECLARE
    l_stadium_id NUMBER;
    l_sector_a   NUMBER;
    l_sector_b   NUMBER;
    l_fan_id     NUMBER;
    l_match_id   NUMBER;
    l_time_id    NUMBER(8);
    l_existing   NUMBER;
    l_total      NUMBER;
BEGIN
    SELECT COUNT(*) INTO l_existing
      FROM dim_match
     WHERE opponent_name LIKE 'TEST PERF %';
    IF l_existing > 0 THEN
        RAISE_APPLICATION_ERROR(-20100,
          'Тестовые матчи уже существуют. Для повторного запуска очистите тестовые матчи и билеты либо создайте новую схему.');
    END IF;

    SELECT MIN(stadium_id) INTO l_stadium_id FROM dim_stadium;
    SELECT MIN(sector_id), MAX(sector_id)
      INTO l_sector_a, l_sector_b
      FROM dim_sector
     WHERE stadium_id=l_stadium_id;
    SELECT MIN(fan_id) INTO l_fan_id FROM dim_fan;

    IF l_stadium_id IS NULL OR l_sector_a IS NULL OR l_sector_b IS NULL OR l_sector_a=l_sector_b OR l_fan_id IS NULL THEN
        RAISE_APPLICATION_ERROR(-20101,'Сначала выполните загрузку демонстрационных данных');
    END IF;

    FOR i IN 1..10 LOOP
        SELECT time_id INTO l_time_id
          FROM dim_time
         WHERE full_date=TRUNC(SYSDATE)+i;

        INSERT INTO dim_match(match_date,time_id,opponent_name,stadium_id,is_home)
        VALUES(TRUNC(SYSDATE)+i,l_time_id,'TEST PERF '||TO_CHAR(i,'FM00'),l_stadium_id,'Y')
        RETURNING match_id INTO l_match_id;

        INSERT INTO tickets(match_id,sector_id,seat_row,seat_number,price,status,
                             fan_id,sale_time_id,reserved_by,reserved_until)
        SELECT l_match_id,
               CASE WHEN q.n <= 5000 THEN l_sector_a ELSE l_sector_b END,
               CEIL(q.seat_pos/100),
               MOD(q.seat_pos-1,100)+1,
               40 + MOD(q.n,5)*5,
               CASE MOD(q.n,4)
                    WHEN 0 THEN 'FREE'
                    WHEN 1 THEN 'RESERVED'
                    WHEN 2 THEN 'SOLD'
                    ELSE 'RETURNED'
               END,
               CASE WHEN MOD(q.n,4)=2 THEN l_fan_id END,
               CASE WHEN MOD(q.n,4)=2 THEN l_time_id END,
               CASE WHEN MOD(q.n,4)=1 THEN l_fan_id END,
               CASE WHEN MOD(q.n,4)=1 THEN SYSDATE+1 END
          FROM (SELECT LEVEL AS n,
                       CASE WHEN LEVEL<=5000 THEN LEVEL ELSE LEVEL-5000 END AS seat_pos
                  FROM dual
                CONNECT BY LEVEL<=10000) q;
    END LOOP;

    SELECT COUNT(*) INTO l_total
      FROM tickets t
      JOIN dim_match m ON m.match_id=t.match_id
     WHERE m.opponent_name LIKE 'TEST PERF %';

    IF l_total < 100000 THEN
        RAISE_APPLICATION_ERROR(-20102,'Не удалось загрузить требуемые 100 000 строк');
    END IF;

    DBMS_STATS.GATHER_TABLE_STATS(USER,'TICKETS',cascade=>TRUE);
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Загружено строк в TICKETS для тестирования: '||l_total);
END;
/
