-- Выполнять после CONNECT HK_USER/...@<PDB_SERVICE>
VAR rc REFCURSOR;
EXEC HK_DINAMO.PKG_USER_API.LIST_PLAYERS(:rc);
PRINT rc;

VAR rc REFCURSOR;
EXEC HK_DINAMO.PKG_USER_API.LIST_MATCHES(DATE '2026-11-01', DATE '2026-12-31', :rc);
PRINT rc;

VAR rc REFCURSOR;
EXEC HK_DINAMO.PKG_USER_API.LIST_FAVORITES(1, :rc);
PRINT rc;

-- Демонстрационный MATCH_ID=1; замените его при изменении seed-данных.
VAR rc REFCURSOR;
EXEC HK_DINAMO.PKG_USER_API.LIST_AVAILABLE_TICKETS(1, :rc);
PRINT rc;

-- Для свежей установки demo_user обычно имеет APP_USER_ID=1,
-- DB_USERNAME='HK_USER', а первый свободный билет обычно TICKET_ID=1.
-- current_fan_id дополнительно проверяет привязку к текущей Oracle-сессии. Раскомментируйте для проверки:
-- EXEC HK_DINAMO.PKG_USER_API.RESERVE_TICKET(1, 1, 15);
-- COMMIT;
