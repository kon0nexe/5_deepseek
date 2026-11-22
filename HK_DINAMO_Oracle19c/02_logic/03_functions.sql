-- =====================================================================
-- Функции для аналитических показателей.
-- =====================================================================
WHENEVER SQLERROR EXIT SQL.SQLCODE

CREATE OR REPLACE FUNCTION f_ticket_revenue(
    p_date_from IN DATE,
    p_date_to   IN DATE
) RETURN NUMBER
AUTHID DEFINER
IS
    l_revenue NUMBER(14,2);
BEGIN
    IF p_date_from IS NULL OR p_date_to IS NULL OR TRUNC(p_date_from) > TRUNC(p_date_to) THEN
        RAISE_APPLICATION_ERROR(-20010, 'Некорректный диапазон дат для расчёта выручки');
    END IF;

    SELECT NVL(SUM(t.price), 0)
      INTO l_revenue
      FROM tickets t
      JOIN dim_time d ON d.time_id = t.sale_time_id
     WHERE t.status = 'SOLD'
       AND d.full_date >= TRUNC(p_date_from)
       AND d.full_date < TRUNC(p_date_to) + 1;

    RETURN l_revenue;
END;
/

CREATE OR REPLACE FUNCTION f_player_popularity(
    p_player_id IN NUMBER
) RETURN NUMBER
AUTHID DEFINER
IS
    l_count NUMBER;
BEGIN
    SELECT COUNT(DISTINCT fan_id)
      INTO l_count
      FROM fan_player_favorites
     WHERE player_id = p_player_id;
    RETURN l_count;
END;
/

PROMPT Функции F_TICKET_REVENUE и F_PLAYER_POPULARITY созданы.
