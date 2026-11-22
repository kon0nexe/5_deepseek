-- =====================================================================
-- Создание владельца схемы и трёх Oracle-пользователей для тестирования.
-- Запускать от SYS в нужной PDB (не в CDB$ROOT).
-- Перед запуском замените пароли CHANGE_ME_* на собственные.
-- Скрипт рассчитан на первое развёртывание; при повторном запуске
-- уже созданные пользователи/роли вызовут ORA-01920/ORA-01921.
-- =====================================================================
WHENEVER SQLERROR EXIT SQL.SQLCODE
SET ECHO OFF

-- Владелец объектов базы данных.
CREATE USER HK_DINAMO IDENTIFIED BY "ChangeMe_Dinamo_19c!"
  DEFAULT TABLESPACE USERS
  TEMPORARY TABLESPACE TEMP
  QUOTA UNLIMITED ON USERS;
GRANT CREATE SESSION, CREATE TABLE, CREATE VIEW, CREATE PROCEDURE,
      CREATE TRIGGER, CREATE SEQUENCE, CREATE TYPE
TO HK_DINAMO;

-- Отдельные Oracle-учётные записи для проверки разграничения доступа.
CREATE USER HK_MAIN_ADMIN IDENTIFIED BY "ChangeMe_MainAdmin_19c!"
  DEFAULT TABLESPACE USERS TEMPORARY TABLESPACE TEMP;
CREATE USER HK_ADMIN IDENTIFIED BY "ChangeMe_Admin_19c!"
  DEFAULT TABLESPACE USERS TEMPORARY TABLESPACE TEMP;
CREATE USER HK_USER IDENTIFIED BY "ChangeMe_User_19c!"
  DEFAULT TABLESPACE USERS TEMPORARY TABLESPACE TEMP;

GRANT CREATE SESSION TO HK_MAIN_ADMIN, HK_ADMIN, HK_USER;

-- Роли Oracle. Привилегии на таблицы напрямую этим ролям не выдаются.
CREATE ROLE HK_USER_ROLE;
CREATE ROLE HK_ADMIN_ROLE;
CREATE ROLE HK_MAIN_ADMIN_ROLE;

-- Администратор получает пользовательские возможности; главный администратор
-- наследует административные и пользовательские возможности.
GRANT HK_USER_ROLE TO HK_ADMIN_ROLE;
GRANT HK_ADMIN_ROLE TO HK_MAIN_ADMIN_ROLE;
GRANT HK_USER_ROLE TO HK_USER;
GRANT HK_ADMIN_ROLE TO HK_ADMIN;
GRANT HK_MAIN_ADMIN_ROLE TO HK_MAIN_ADMIN;

-- Каталог для JSON-файлов. Физический каталог должен существовать
-- внутри контейнера и быть доступен ОС-пользователю oracle.
CREATE OR REPLACE DIRECTORY HK_JSON_DIR AS '/opt/oracle/json';
GRANT READ, WRITE ON DIRECTORY HK_JSON_DIR TO HK_DINAMO;

-- Прямые EXECUTE-привилегии владельцу необходимы для компиляции
-- хранимого кода, который обращается к системным пакетам.
GRANT EXECUTE ON SYS.UTL_FILE TO HK_DINAMO;
GRANT EXECUTE ON SYS.DBMS_LOB TO HK_DINAMO;
GRANT EXECUTE ON SYS.DBMS_STATS TO HK_DINAMO;

PROMPT =============================================================
PROMPT Созданы HK_DINAMO, HK_MAIN_ADMIN, HK_ADMIN, HK_USER и роли.
PROMPT Смените пароли и продолжите установку от HK_DINAMO.
PROMPT =============================================================
