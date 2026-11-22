-- Выполнять от SYS (SYSDBA) в пользовательской PDB, НЕ в CDB$ROOT.
-- Перед запуском замени пароль HK_WEB_APP на собственный и такой же укажи в .env.
WHENEVER SQLERROR EXIT SQL.SQLCODE
SET ECHO ON

-- Для повторного запуска существующая учётная запись не удаляется.
DECLARE
    l_count NUMBER;
BEGIN
    SELECT COUNT(*) INTO l_count FROM all_users WHERE username='HK_WEB_APP';
    IF l_count=0 THEN
        EXECUTE IMMEDIATE 'CREATE USER HK_WEB_APP IDENTIFIED BY "ChangeMe_WebApp_19c!" DEFAULT TABLESPACE USERS TEMPORARY TABLESPACE TEMP';
    ELSE
        EXECUTE IMMEDIATE 'ALTER USER HK_WEB_APP IDENTIFIED BY "ChangeMe_WebApp_19c!" ACCOUNT UNLOCK';
    END IF;
END;
/
GRANT CREATE SESSION TO HK_WEB_APP;
GRANT EXECUTE ON HK_DINAMO.PKG_WEB_API TO HK_WEB_APP;

PROMPT HK_WEB_APP создан/обновлён. У него есть CREATE SESSION и EXECUTE только на HK_DINAMO.PKG_WEB_API.
