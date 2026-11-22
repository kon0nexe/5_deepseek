-- ============================================================================
-- Восстановление демонстрационного матча и подготовка 10 000 мест.
-- Выполнять от HK_DINAMO в PDB ORCLPDB1 (SQL Developer, F5).
--
-- Основание: при диагностике обнаружен матч MATCH_ID=1 на 2026-11-20,
-- арена STADIUM_ID=1 и два сектора A/B по 5 000 мест, но текстовые названия
-- не совпадали с Unicode-литералами в PKG_WEB_API. Поэтому генератор мест
-- пропустил матч. Скрипт исправляет только этот демонстрационный матч и
-- названия его арены, затем добавляет только отсутствующие места.
-- Он НЕ удаляет строки, не меняет 100 000 тестовых билетов и не пересоздаёт
-- объекты схемы. Повторный запуск безопасен: дубли мест исключены.
-- ============================================================================
WHENEVER SQLERROR EXIT SQL.SQLCODE
SET SERVEROUTPUT ON
SET DEFINE OFF

DECLARE
    c_demo_match_id CONSTANT NUMBER := 1;
    c_demo_date     CONSTANT DATE := DATE '2026-11-20';
    l_stadium_id    NUMBER;
    l_sector_a      NUMBER;
    l_sector_b      NUMBER;
    l_match_count   NUMBER;
    l_added_a       NUMBER := 0;
    l_added_b       NUMBER := 0;
    l_total         NUMBER;
BEGIN
    -- Не затрагиваем никакой матч, кроме подтверждённого диагностикой MATCH_ID=1.
    SELECT COUNT(*)
      INTO l_match_count
      FROM dim_match
     WHERE match_id = c_demo_match_id
       AND TRUNC(match_date) = c_demo_date
       AND match_status <> 'CANCELLED';

    IF l_match_count <> 1 THEN
        RAISE_APPLICATION_ERROR(-20201,
          'Ожидаемый демонстрационный матч MATCH_ID=1 на 2026-11-20 не найден или неоднозначен. Изменения не внесены.');
    END IF;

    SELECT stadium_id
      INTO l_stadium_id
      FROM dim_match
     WHERE match_id = c_demo_match_id;

    -- Исправляем Unicode-названия, если они были повреждены при первоначальном
    -- запуске SQL*Plus. UNISTR не зависит от кодовой страницы файла/терминала.
    UPDATE dim_stadium
       SET name = UNISTR('\041C\0438\043D\0441\043A-\0410\0440\0435\043D\0430'),
           city = UNISTR('\041C\0438\043D\0441\043A')
     WHERE stadium_id = l_stadium_id;

    UPDATE dim_match
       SET opponent_name = UNISTR('\0414\0435\043C\043E\043D\0441\0442\0440\0430\0446\0438\043E\043D\043D\044B\0439 \0441\043E\043F\0435\0440\043D\0438\043A')
     WHERE match_id = c_demo_match_id;

    SELECT sector_id
      INTO l_sector_a
      FROM dim_sector
     WHERE stadium_id = l_stadium_id
       AND sector_code = 'A';

    SELECT sector_id
      INTO l_sector_b
      FROM dim_sector
     WHERE stadium_id = l_stadium_id
       AND sector_code = 'B';

    -- На каждый сектор: 50 рядов по 100 мест. Уже существующие 4 примера
    -- билетов сохраняются со своими FREE/RESERVED/SOLD/RETURNED статусами.
    INSERT INTO tickets(match_id, sector_id, seat_row, seat_number, price, status)
    SELECT c_demo_match_id, l_sector_a,
           CEIL(q.n / 100), MOD(q.n - 1, 100) + 1, 45, 'FREE'
      FROM (SELECT LEVEL AS n FROM dual CONNECT BY LEVEL <= 5000) q
     WHERE NOT EXISTS (
           SELECT 1 FROM tickets t
            WHERE t.match_id = c_demo_match_id
              AND t.sector_id = l_sector_a
              AND t.seat_row = CEIL(q.n / 100)
              AND t.seat_number = MOD(q.n - 1, 100) + 1
     );
    l_added_a := SQL%ROWCOUNT;

    INSERT INTO tickets(match_id, sector_id, seat_row, seat_number, price, status)
    SELECT c_demo_match_id, l_sector_b,
           CEIL(q.n / 100), MOD(q.n - 1, 100) + 1, 55, 'FREE'
      FROM (SELECT LEVEL AS n FROM dual CONNECT BY LEVEL <= 5000) q
     WHERE NOT EXISTS (
           SELECT 1 FROM tickets t
            WHERE t.match_id = c_demo_match_id
              AND t.sector_id = l_sector_b
              AND t.seat_row = CEIL(q.n / 100)
              AND t.seat_number = MOD(q.n - 1, 100) + 1
     );
    l_added_b := SQL%ROWCOUNT;

    SELECT COUNT(*)
      INTO l_total
      FROM tickets
     WHERE match_id = c_demo_match_id
       AND sector_id IN (l_sector_a, l_sector_b);

    IF l_total <> 10000 THEN
        RAISE_APPLICATION_ERROR(-20202,
          'После подготовки ожидалось ровно 10000 мест; фактически: ' || l_total);
    END IF;

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Демонстрационный матч: MATCH_ID=' || c_demo_match_id);
    DBMS_OUTPUT.PUT_LINE('Добавлено мест в сектор A: ' || l_added_a);
    DBMS_OUTPUT.PUT_LINE('Добавлено мест в сектор B: ' || l_added_b);
    DBMS_OUTPUT.PUT_LINE('Всего мест в демонстрационном матче: ' || l_total);
    DBMS_OUTPUT.PUT_LINE('100 000 тестовых билетов не изменялись.');
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END;
/

PROMPT === Проверка демонстрационного матча и мест ===
SELECT m.match_id,
       TO_CHAR(m.match_date, 'YYYY-MM-DD') AS match_date,
       m.opponent_name,
       s.name AS stadium,
       COUNT(t.ticket_id) AS demo_seats,
       COUNT(DISTINCT t.sector_id) AS sectors,
       COUNT(DISTINCT t.seat_row) AS distinct_rows
  FROM dim_match m
  JOIN dim_stadium s ON s.stadium_id = m.stadium_id
  LEFT JOIN tickets t ON t.match_id = m.match_id
 WHERE m.match_id = 1
 GROUP BY m.match_id, m.match_date, m.opponent_name, s.name;

SELECT t.status, COUNT(*) AS tickets_count
  FROM tickets t
 WHERE t.match_id = 1
 GROUP BY t.status
 ORDER BY t.status;
