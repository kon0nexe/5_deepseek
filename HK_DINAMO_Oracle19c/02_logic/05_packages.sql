-- =====================================================================
-- Пакеты серверной логики: пользовательские операции, администрирование,
-- управление прикладными учётными записями и JSON-импорт/экспорт.
-- Все пакеты работают с правами владельца (AUTHID DEFINER).
-- =====================================================================
WHENEVER SQLERROR EXIT SQL.SQLCODE

-- ---------------------------------------------------------------------
-- Пакет административных операций с предметными данными.
-- ---------------------------------------------------------------------
CREATE OR REPLACE PACKAGE pkg_admin_api AUTHID DEFINER AS
    PROCEDURE add_player(
        p_first_name IN VARCHAR2, p_last_name IN VARCHAR2,
        p_position IN VARCHAR2, p_jersey_number IN NUMBER,
        p_birth_date IN DATE, p_country IN VARCHAR2,
        p_height_cm IN NUMBER, p_weight_kg IN NUMBER,
        p_player_id OUT NUMBER);

    PROCEDURE update_player(
        p_player_id IN NUMBER, p_first_name IN VARCHAR2,
        p_last_name IN VARCHAR2, p_position IN VARCHAR2,
        p_jersey_number IN NUMBER, p_birth_date IN DATE,
        p_country IN VARCHAR2, p_height_cm IN NUMBER,
        p_weight_kg IN NUMBER, p_is_active IN CHAR);

    PROCEDURE delete_player(p_player_id IN NUMBER);

    PROCEDURE add_match(
        p_match_date IN DATE, p_opponent_name IN VARCHAR2,
        p_stadium_id IN NUMBER, p_is_home IN CHAR,
        p_match_id OUT NUMBER);

    PROCEDURE update_match(
        p_match_id IN NUMBER, p_match_date IN DATE,
        p_opponent_name IN VARCHAR2, p_stadium_id IN NUMBER,
        p_is_home IN CHAR, p_match_status IN VARCHAR2,
        p_goals_for IN NUMBER, p_goals_against IN NUMBER);

    PROCEDURE delete_match(p_match_id IN NUMBER);

    PROCEDURE add_ticket(
        p_match_id IN NUMBER, p_sector_id IN NUMBER,
        p_seat_row IN NUMBER, p_seat_number IN NUMBER,
        p_price IN NUMBER, p_ticket_id OUT NUMBER);

    PROCEDURE sell_ticket(p_ticket_id IN NUMBER, p_fan_id IN NUMBER);
    PROCEDURE return_ticket(p_ticket_id IN NUMBER);
    PROCEDURE release_expired_reservations(p_released_count OUT NUMBER);

    PROCEDURE add_merch(
        p_name IN VARCHAR2, p_category IN VARCHAR2,
        p_price IN NUMBER, p_description IN VARCHAR2,
        p_merch_id OUT NUMBER);

    PROCEDURE update_merch(
        p_merch_id IN NUMBER, p_name IN VARCHAR2,
        p_category IN VARCHAR2, p_price IN NUMBER,
        p_description IN VARCHAR2, p_is_active IN CHAR);

    PROCEDURE delete_merch(p_merch_id IN NUMBER);

    PROCEDURE add_merch_order(
        p_merch_id IN NUMBER, p_fan_id IN NUMBER,
        p_time_id IN NUMBER, p_quantity IN NUMBER,
        p_order_id OUT NUMBER);

    PROCEDURE ticket_sales_report(p_date_from IN DATE, p_date_to IN DATE,
                                  p_result OUT SYS_REFCURSOR);
    PROCEDURE player_popularity_report(p_result OUT SYS_REFCURSOR);
END pkg_admin_api;
/

CREATE OR REPLACE PACKAGE BODY pkg_admin_api AS
    PROCEDURE add_player(
        p_first_name IN VARCHAR2, p_last_name IN VARCHAR2,
        p_position IN VARCHAR2, p_jersey_number IN NUMBER,
        p_birth_date IN DATE, p_country IN VARCHAR2,
        p_height_cm IN NUMBER, p_weight_kg IN NUMBER,
        p_player_id OUT NUMBER) IS
    BEGIN
        INSERT INTO dim_player(first_name,last_name,position,jersey_number,
                               birth_date,country,height_cm,weight_kg)
        VALUES (TRIM(p_first_name),TRIM(p_last_name),UPPER(TRIM(p_position)),
                p_jersey_number,p_birth_date,p_country,p_height_cm,p_weight_kg)
        RETURNING player_id INTO p_player_id;
    END;

    PROCEDURE update_player(
        p_player_id IN NUMBER, p_first_name IN VARCHAR2,
        p_last_name IN VARCHAR2, p_position IN VARCHAR2,
        p_jersey_number IN NUMBER, p_birth_date IN DATE,
        p_country IN VARCHAR2, p_height_cm IN NUMBER,
        p_weight_kg IN NUMBER, p_is_active IN CHAR) IS
    BEGIN
        UPDATE dim_player
           SET first_name=TRIM(p_first_name), last_name=TRIM(p_last_name),
               position=UPPER(TRIM(p_position)), jersey_number=p_jersey_number,
               birth_date=p_birth_date, country=p_country,
               height_cm=p_height_cm, weight_kg=p_weight_kg,
               is_active=UPPER(p_is_active)
         WHERE player_id=p_player_id;
        IF SQL%ROWCOUNT=0 THEN
            RAISE_APPLICATION_ERROR(-20020,'Игрок не найден');
        END IF;
    END;

    PROCEDURE delete_player(p_player_id IN NUMBER) IS
    BEGIN
        DELETE FROM dim_player WHERE player_id=p_player_id;
        IF SQL%ROWCOUNT=0 THEN
            RAISE_APPLICATION_ERROR(-20021,'Игрок не найден');
        END IF;
        -- Если игрок уже присутствует в статистике или избранном,
        -- Oracle запретит удаление по внешнему ключу. В таком случае
        -- рекомендуется использовать UPDATE is_active='N'.
    END;

    PROCEDURE add_match(
        p_match_date IN DATE, p_opponent_name IN VARCHAR2,
        p_stadium_id IN NUMBER, p_is_home IN CHAR,
        p_match_id OUT NUMBER) IS
        l_time_id NUMBER(8);
    BEGIN
        SELECT time_id INTO l_time_id
          FROM dim_time
         WHERE full_date=TRUNC(p_match_date);
        INSERT INTO dim_match(match_date,time_id,opponent_name,stadium_id,is_home)
        VALUES(p_match_date,l_time_id,TRIM(p_opponent_name),p_stadium_id,UPPER(p_is_home))
        RETURNING match_id INTO p_match_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20022,'Для даты матча отсутствует строка в DIM_TIME');
    END;

    PROCEDURE update_match(
        p_match_id IN NUMBER, p_match_date IN DATE,
        p_opponent_name IN VARCHAR2, p_stadium_id IN NUMBER,
        p_is_home IN CHAR, p_match_status IN VARCHAR2,
        p_goals_for IN NUMBER, p_goals_against IN NUMBER) IS
        l_time_id NUMBER(8);
    BEGIN
        SELECT time_id INTO l_time_id
          FROM dim_time
         WHERE full_date=TRUNC(p_match_date);
        UPDATE dim_match
           SET match_date=p_match_date, time_id=l_time_id,
               opponent_name=TRIM(p_opponent_name), stadium_id=p_stadium_id,
               is_home=UPPER(p_is_home), match_status=UPPER(p_match_status),
               goals_for=p_goals_for, goals_against=p_goals_against
         WHERE match_id=p_match_id;
        IF SQL%ROWCOUNT=0 THEN
            RAISE_APPLICATION_ERROR(-20023,'Матч не найден');
        END IF;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20022,'Для даты матча отсутствует строка в DIM_TIME');
    END;

    PROCEDURE delete_match(p_match_id IN NUMBER) IS
    BEGIN
        DELETE FROM dim_match WHERE match_id=p_match_id;
        IF SQL%ROWCOUNT=0 THEN
            RAISE_APPLICATION_ERROR(-20024,'Матч не найден');
        END IF;
    END;

    PROCEDURE add_ticket(
        p_match_id IN NUMBER, p_sector_id IN NUMBER,
        p_seat_row IN NUMBER, p_seat_number IN NUMBER,
        p_price IN NUMBER, p_ticket_id OUT NUMBER) IS
    BEGIN
        INSERT INTO tickets(match_id,sector_id,seat_row,seat_number,price,status)
        VALUES(p_match_id,p_sector_id,p_seat_row,p_seat_number,p_price,'FREE')
        RETURNING ticket_id INTO p_ticket_id;
    END;

    PROCEDURE sell_ticket(p_ticket_id IN NUMBER, p_fan_id IN NUMBER) IS
        l_status VARCHAR2(10);
        l_time_id NUMBER(8);
    BEGIN
        SELECT status INTO l_status
          FROM tickets
         WHERE ticket_id=p_ticket_id
           FOR UPDATE;
        IF l_status NOT IN ('FREE','RESERVED','RETURNED') THEN
            RAISE_APPLICATION_ERROR(-20025,'Билет нельзя продать в текущем статусе');
        END IF;
        SELECT time_id INTO l_time_id
          FROM dim_time
         WHERE full_date=TRUNC(SYSDATE);
        UPDATE tickets
           SET status='SOLD', fan_id=p_fan_id, sale_time_id=l_time_id,
               reserved_by=NULL, reserved_until=NULL
         WHERE ticket_id=p_ticket_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20026,'Билет не найден или текущая дата отсутствует в DIM_TIME');
    END;

    PROCEDURE return_ticket(p_ticket_id IN NUMBER) IS
        l_status VARCHAR2(10);
    BEGIN
        SELECT status INTO l_status
          FROM tickets
         WHERE ticket_id=p_ticket_id
           FOR UPDATE;
        IF l_status <> 'SOLD' THEN
            RAISE_APPLICATION_ERROR(-20027,'Возврат возможен только для проданного билета');
        END IF;
        UPDATE tickets
           SET status='RETURNED', reserved_by=NULL, reserved_until=NULL
         WHERE ticket_id=p_ticket_id;
        -- fan_id и sale_time_id сохраняются как сведения о состоявшейся продаже.
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20026,'Билет не найден');
    END;

    PROCEDURE release_expired_reservations(p_released_count OUT NUMBER) IS
    BEGIN
        UPDATE tickets
           SET status='FREE', reserved_by=NULL, reserved_until=NULL
         WHERE status='RESERVED' AND reserved_until <= SYSDATE;
        p_released_count := SQL%ROWCOUNT;
    END;

    PROCEDURE add_merch(
        p_name IN VARCHAR2, p_category IN VARCHAR2,
        p_price IN NUMBER, p_description IN VARCHAR2,
        p_merch_id OUT NUMBER) IS
    BEGIN
        INSERT INTO dim_merch(name,category,price,description)
        VALUES(TRIM(p_name),TRIM(p_category),p_price,p_description)
        RETURNING merch_id INTO p_merch_id;
    END;

    PROCEDURE update_merch(
        p_merch_id IN NUMBER, p_name IN VARCHAR2,
        p_category IN VARCHAR2, p_price IN NUMBER,
        p_description IN VARCHAR2, p_is_active IN CHAR) IS
    BEGIN
        UPDATE dim_merch
           SET name=TRIM(p_name), category=TRIM(p_category), price=p_price,
               description=p_description, is_active=UPPER(p_is_active)
         WHERE merch_id=p_merch_id;
        IF SQL%ROWCOUNT=0 THEN
            RAISE_APPLICATION_ERROR(-20028,'Товар не найден');
        END IF;
    END;

    PROCEDURE delete_merch(p_merch_id IN NUMBER) IS
    BEGIN
        DELETE FROM dim_merch WHERE merch_id=p_merch_id;
        IF SQL%ROWCOUNT=0 THEN
            RAISE_APPLICATION_ERROR(-20029,'Товар не найден');
        END IF;
    END;

    PROCEDURE add_merch_order(
        p_merch_id IN NUMBER, p_fan_id IN NUMBER,
        p_time_id IN NUMBER, p_quantity IN NUMBER,
        p_order_id OUT NUMBER) IS
        l_price NUMBER(10,2);
    BEGIN
        SELECT price INTO l_price
          FROM dim_merch
         WHERE merch_id=p_merch_id AND is_active='Y';
        INSERT INTO merch_orders(merch_id,fan_id,time_id,quantity,unit_price,status)
        VALUES(p_merch_id,p_fan_id,p_time_id,p_quantity,l_price,'COMPLETED')
        RETURNING order_id INTO p_order_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20030,'Активный товар не найден');
    END;

    PROCEDURE ticket_sales_report(p_date_from IN DATE, p_date_to IN DATE,
                                  p_result OUT SYS_REFCURSOR) IS
    BEGIN
        OPEN p_result FOR
            SELECT full_date, year_num, month_num, month_name, season,
                   tickets_sold, revenue
              FROM v_ticket_sales_by_period
             WHERE (p_date_from IS NULL OR full_date >= TRUNC(p_date_from))
               AND (p_date_to IS NULL OR full_date < TRUNC(p_date_to)+1)
             ORDER BY full_date;
    END;

    PROCEDURE player_popularity_report(p_result OUT SYS_REFCURSOR) IS
    BEGIN
        OPEN p_result FOR
            SELECT player_id, first_name, last_name, fans_favorited
              FROM v_player_popularity
             ORDER BY fans_favorited DESC, last_name, first_name;
    END;
END pkg_admin_api;
/

-- ---------------------------------------------------------------------
-- Пакет действий пользователя. Профиль болельщика определяется по
-- APP_USERS.FAN_ID после проверки активной прикладной записи с ролью USER.
-- ---------------------------------------------------------------------
CREATE OR REPLACE PACKAGE pkg_user_api AUTHID DEFINER AS
    PROCEDURE list_players(p_result OUT SYS_REFCURSOR);
    PROCEDURE list_matches(p_date_from IN DATE, p_date_to IN DATE,
                           p_result OUT SYS_REFCURSOR);
    PROCEDURE list_available_tickets(p_match_id IN NUMBER,
                                     p_result OUT SYS_REFCURSOR);
    PROCEDURE list_merch(p_result OUT SYS_REFCURSOR);
    PROCEDURE reserve_ticket(p_ticket_id IN NUMBER, p_app_user_id IN NUMBER,
                             p_minutes IN NUMBER DEFAULT 15);
    PROCEDURE add_favorite(p_app_user_id IN NUMBER, p_player_id IN NUMBER);
    PROCEDURE remove_favorite(p_app_user_id IN NUMBER, p_player_id IN NUMBER);
    PROCEDURE list_favorites(p_app_user_id IN NUMBER, p_result OUT SYS_REFCURSOR);
END pkg_user_api;
/

CREATE OR REPLACE PACKAGE BODY pkg_user_api AS
    FUNCTION current_fan_id(p_app_user_id IN NUMBER) RETURN NUMBER IS
        l_fan_id NUMBER;
    BEGIN
        SELECT fan_id INTO l_fan_id
          FROM app_users
         WHERE user_id=p_app_user_id
           AND is_active='Y'
           AND role='USER'
           AND fan_id IS NOT NULL
           AND UPPER(db_username)=SYS_CONTEXT('USERENV','SESSION_USER');
        RETURN l_fan_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20040,
              'Для текущего Oracle-сеанса не найдена активная APP_USERS-запись USER с привязанным DIM_FAN');
    END;

    PROCEDURE list_players(p_result OUT SYS_REFCURSOR) IS
    BEGIN
        OPEN p_result FOR
            SELECT player_id, first_name, last_name, position, jersey_number,
                   birth_date, country, is_active
              FROM dim_player
             WHERE is_active='Y'
             ORDER BY last_name, first_name;
    END;

    PROCEDURE list_matches(p_date_from IN DATE, p_date_to IN DATE,
                           p_result OUT SYS_REFCURSOR) IS
    BEGIN
        OPEN p_result FOR
            SELECT m.match_id, m.match_date, m.opponent_name, s.name AS stadium,
                   m.is_home, m.goals_for, m.goals_against, m.match_status
              FROM dim_match m
              JOIN dim_stadium s ON s.stadium_id=m.stadium_id
             WHERE (p_date_from IS NULL OR m.match_date >= TRUNC(p_date_from))
               AND (p_date_to IS NULL OR m.match_date < TRUNC(p_date_to)+1)
             ORDER BY m.match_date;
    END;

    PROCEDURE list_available_tickets(p_match_id IN NUMBER,
                                     p_result OUT SYS_REFCURSOR) IS
    BEGIN
        OPEN p_result FOR
            SELECT t.ticket_id, t.match_id, s.sector_code, t.seat_row,
                   t.seat_number, t.price, t.status
              FROM tickets t
              JOIN dim_sector s ON s.sector_id=t.sector_id
             WHERE t.match_id=p_match_id
               AND (t.status='FREE' OR
                    (t.status='RESERVED' AND t.reserved_until <= SYSDATE))
             ORDER BY s.sector_code, t.seat_row, t.seat_number;
    END;

    PROCEDURE list_merch(p_result OUT SYS_REFCURSOR) IS
    BEGIN
        OPEN p_result FOR
            SELECT merch_id, name, category, price, description
              FROM dim_merch
             WHERE is_active='Y'
             ORDER BY category, name;
    END;

    PROCEDURE reserve_ticket(p_ticket_id IN NUMBER, p_app_user_id IN NUMBER,
                             p_minutes IN NUMBER DEFAULT 15) IS
        l_fan_id NUMBER;
        l_status VARCHAR2(10);
        l_reserved_until DATE;
    BEGIN
        IF p_minutes IS NULL OR p_minutes < 1 OR p_minutes > 120 THEN
            RAISE_APPLICATION_ERROR(-20042,'Срок резерва должен составлять от 1 до 120 минут');
        END IF;
        l_fan_id := current_fan_id(p_app_user_id);
        SELECT status, reserved_until
          INTO l_status, l_reserved_until
          FROM tickets
         WHERE ticket_id=p_ticket_id
           FOR UPDATE;

        IF l_status='RESERVED' AND l_reserved_until <= SYSDATE THEN
            UPDATE tickets
               SET status='FREE', reserved_by=NULL, reserved_until=NULL
             WHERE ticket_id=p_ticket_id;
            l_status := 'FREE';
        END IF;

        IF l_status NOT IN ('FREE','RETURNED') THEN
            RAISE_APPLICATION_ERROR(-20043,'Билет уже продан или зарезервирован');
        END IF;

        UPDATE tickets
           SET status='RESERVED', fan_id=NULL, sale_time_id=NULL,
               reserved_by=l_fan_id, reserved_until=SYSDATE+(p_minutes/1440)
         WHERE ticket_id=p_ticket_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20044,'Билет не найден');
    END;

    PROCEDURE add_favorite(p_app_user_id IN NUMBER, p_player_id IN NUMBER) IS
        l_fan_id NUMBER;
    BEGIN
        l_fan_id := current_fan_id(p_app_user_id);
        INSERT INTO fan_player_favorites(fan_id,player_id)
        VALUES(l_fan_id,p_player_id);
    EXCEPTION
        WHEN DUP_VAL_ON_INDEX THEN
            RAISE_APPLICATION_ERROR(-20045,'Игрок уже находится в списке избранного');
    END;

    PROCEDURE remove_favorite(p_app_user_id IN NUMBER, p_player_id IN NUMBER) IS
        l_fan_id NUMBER;
    BEGIN
        l_fan_id := current_fan_id(p_app_user_id);
        DELETE FROM fan_player_favorites
         WHERE fan_id=l_fan_id AND player_id=p_player_id;
        IF SQL%ROWCOUNT=0 THEN
            RAISE_APPLICATION_ERROR(-20046,'Игрок не найден в списке избранного');
        END IF;
    END;

    PROCEDURE list_favorites(p_app_user_id IN NUMBER, p_result OUT SYS_REFCURSOR) IS
        l_fan_id NUMBER;
    BEGIN
        l_fan_id := current_fan_id(p_app_user_id);
        OPEN p_result FOR
            SELECT p.player_id,p.first_name,p.last_name,p.position,f.created_at
              FROM fan_player_favorites f
              JOIN dim_player p ON p.player_id=f.player_id
             WHERE f.fan_id=l_fan_id
             ORDER BY f.created_at DESC;
    END;

END pkg_user_api;
/

-- ---------------------------------------------------------------------
-- Управление прикладными учётными записями. Доступ получает только
-- главная административная роль Oracle.
-- ---------------------------------------------------------------------
CREATE OR REPLACE PACKAGE pkg_security_api AUTHID DEFINER AS
    PROCEDURE create_app_user(
        p_username IN VARCHAR2, p_password_hash IN VARCHAR2,
        p_email IN VARCHAR2, p_role IN VARCHAR2,
        p_fan_id IN NUMBER, p_user_id OUT NUMBER);
    PROCEDURE change_app_user_role(p_user_id IN NUMBER, p_role IN VARCHAR2);
    PROCEDURE set_app_user_active(p_user_id IN NUMBER, p_is_active IN CHAR);
    PROCEDURE bind_app_user_db_user(p_user_id IN NUMBER, p_db_username IN VARCHAR2);
END pkg_security_api;
/

CREATE OR REPLACE PACKAGE BODY pkg_security_api AS
    PROCEDURE create_app_user(
        p_username IN VARCHAR2, p_password_hash IN VARCHAR2,
        p_email IN VARCHAR2, p_role IN VARCHAR2,
        p_fan_id IN NUMBER, p_user_id OUT NUMBER) IS
        l_role VARCHAR2(20);
    BEGIN
        l_role := UPPER(TRIM(p_role));
        IF l_role NOT IN ('MAIN_ADMIN','ADMIN','USER') THEN
            RAISE_APPLICATION_ERROR(-20050,'Недопустимая прикладная роль');
        END IF;
        IF p_password_hash IS NULL OR LENGTH(TRIM(p_password_hash)) < 20 THEN
            RAISE_APPLICATION_ERROR(-20051,'Передайте хеш пароля, а не открытый пароль');
        END IF;
        INSERT INTO app_users(username,password_hash,email,role,fan_id)
        VALUES(TRIM(p_username),p_password_hash,LOWER(TRIM(p_email)),l_role,p_fan_id)
        RETURNING user_id INTO p_user_id;
    END;

    PROCEDURE change_app_user_role(p_user_id IN NUMBER, p_role IN VARCHAR2) IS
        l_role VARCHAR2(20);
    BEGIN
        l_role := UPPER(TRIM(p_role));
        IF l_role NOT IN ('MAIN_ADMIN','ADMIN','USER') THEN
            RAISE_APPLICATION_ERROR(-20050,'Недопустимая прикладная роль');
        END IF;
        UPDATE app_users SET role=l_role WHERE user_id=p_user_id;
        IF SQL%ROWCOUNT=0 THEN
            RAISE_APPLICATION_ERROR(-20052,'Прикладная учётная запись не найдена');
        END IF;
    END;

    PROCEDURE set_app_user_active(p_user_id IN NUMBER, p_is_active IN CHAR) IS
    BEGIN
        IF UPPER(p_is_active) NOT IN ('Y','N') THEN
            RAISE_APPLICATION_ERROR(-20053,'Признак активности должен быть Y или N');
        END IF;
        UPDATE app_users SET is_active=UPPER(p_is_active) WHERE user_id=p_user_id;
        IF SQL%ROWCOUNT=0 THEN
            RAISE_APPLICATION_ERROR(-20052,'Прикладная учётная запись не найдена');
        END IF;
    END;

    PROCEDURE bind_app_user_db_user(p_user_id IN NUMBER, p_db_username IN VARCHAR2) IS
        l_count PLS_INTEGER;
    BEGIN
        IF p_db_username IS NULL OR TRIM(p_db_username) IS NULL THEN
            RAISE_APPLICATION_ERROR(-20054,'Необходимо указать Oracle-пользователя');
        END IF;
        SELECT COUNT(*) INTO l_count
          FROM all_users
         WHERE username=UPPER(TRIM(p_db_username));
        IF l_count=0 THEN
            RAISE_APPLICATION_ERROR(-20055,'Указанный Oracle-пользователь не существует');
        END IF;
        UPDATE app_users
           SET db_username=UPPER(TRIM(p_db_username))
         WHERE user_id=p_user_id;
        IF SQL%ROWCOUNT=0 THEN
            RAISE_APPLICATION_ERROR(-20052,'Прикладная учётная запись не найдена');
        END IF;
    END;
END pkg_security_api;
/

-- ---------------------------------------------------------------------
-- Импорт/экспорт JSON-файлов. Ожидается файл UTF-8 с объектом вида
-- {"players":[{...}, ...]}. Для файлов используется DIRECTORY HK_JSON_DIR.
-- ---------------------------------------------------------------------
CREATE OR REPLACE PACKAGE pkg_json_io AUTHID DEFINER AS
    PROCEDURE import_players(p_file_name IN VARCHAR2);
    PROCEDURE export_players(p_file_name IN VARCHAR2);
END pkg_json_io;
/

CREATE OR REPLACE PACKAGE BODY pkg_json_io AS
    PROCEDURE read_file_to_clob(p_file_name IN VARCHAR2, p_json OUT CLOB) IS
        l_file UTL_FILE.FILE_TYPE;
        l_line VARCHAR2(32767);
    BEGIN
        DBMS_LOB.CREATETEMPORARY(p_json, TRUE);
        l_file := UTL_FILE.FOPEN('HK_JSON_DIR',p_file_name,'R',32767);
        LOOP
            BEGIN
                UTL_FILE.GET_LINE(l_file,l_line);
                DBMS_LOB.WRITEAPPEND(p_json,LENGTH(l_line),l_line);
                DBMS_LOB.WRITEAPPEND(p_json,1,CHR(10));
            EXCEPTION
                WHEN NO_DATA_FOUND THEN EXIT;
            END;
        END LOOP;
        UTL_FILE.FCLOSE(l_file);
    EXCEPTION
        WHEN OTHERS THEN
            IF UTL_FILE.IS_OPEN(l_file) THEN UTL_FILE.FCLOSE(l_file); END IF;
            IF p_json IS NOT NULL AND DBMS_LOB.ISTEMPORARY(p_json)=1 THEN
                DBMS_LOB.FREETEMPORARY(p_json);
            END IF;
            RAISE;
    END;

    PROCEDURE import_players(p_file_name IN VARCHAR2) IS
        l_json CLOB;
    BEGIN
        read_file_to_clob(p_file_name,l_json);
        INSERT INTO dim_player(first_name,last_name,position,jersey_number,
                               birth_date,country,height_cm,weight_kg)
        SELECT jt.first_name,
               jt.last_name,
               UPPER(jt.position),
               jt.jersey_number,
               CASE WHEN jt.birth_date IS NOT NULL
                    THEN TO_DATE(jt.birth_date,'YYYY-MM-DD') END,
               jt.country,
               jt.height_cm,
               jt.weight_kg
          FROM JSON_TABLE(l_json,'$.players[*]'
                 COLUMNS (
                   first_name    VARCHAR2(50) PATH '$.first_name',
                   last_name     VARCHAR2(50) PATH '$.last_name',
                   position      VARCHAR2(15) PATH '$.position',
                   jersey_number NUMBER       PATH '$.jersey_number' NULL ON ERROR,
                   birth_date    VARCHAR2(10) PATH '$.birth_date' NULL ON ERROR,
                   country       VARCHAR2(50) PATH '$.country' NULL ON ERROR,
                   height_cm     NUMBER       PATH '$.height_cm' NULL ON ERROR,
                   weight_kg     NUMBER       PATH '$.weight_kg' NULL ON ERROR
                 )) jt;
        DBMS_LOB.FREETEMPORARY(l_json);
    EXCEPTION
        WHEN OTHERS THEN
            IF l_json IS NOT NULL AND DBMS_LOB.ISTEMPORARY(l_json)=1 THEN
                DBMS_LOB.FREETEMPORARY(l_json);
            END IF;
            RAISE;
    END;

    PROCEDURE export_players(p_file_name IN VARCHAR2) IS
        l_json CLOB;
        l_file UTL_FILE.FILE_TYPE;
        l_offset PLS_INTEGER := 1;
        l_chunk VARCHAR2(32767);
        l_length PLS_INTEGER;
    BEGIN
        SELECT JSON_OBJECT(
                 'players' VALUE (
                   SELECT JSON_ARRAYAGG(
                            JSON_OBJECT(
                              'player_id' VALUE player_id,
                              'first_name' VALUE first_name,
                              'last_name' VALUE last_name,
                              'position' VALUE position,
                              'jersey_number' VALUE jersey_number,
                              'birth_date' VALUE CASE WHEN birth_date IS NOT NULL
                                                       THEN TO_CHAR(birth_date,'YYYY-MM-DD') END,
                              'country' VALUE country,
                              'height_cm' VALUE height_cm,
                              'weight_kg' VALUE weight_kg,
                              'is_active' VALUE is_active
                              NULL ON NULL RETURNING CLOB
                            ) RETURNING CLOB
                          )
                     FROM dim_player
                 ) FORMAT JSON
                 RETURNING CLOB
               )
          INTO l_json
          FROM dual;

        l_file := UTL_FILE.FOPEN('HK_JSON_DIR',p_file_name,'W',32767);
        l_length := DBMS_LOB.GETLENGTH(l_json);
        WHILE l_offset <= l_length LOOP
            l_chunk := DBMS_LOB.SUBSTR(l_json,32767,l_offset);
            UTL_FILE.PUT(l_file,l_chunk);
            l_offset := l_offset + LENGTH(l_chunk);
        END LOOP;
        UTL_FILE.NEW_LINE(l_file);
        UTL_FILE.FCLOSE(l_file);
        DBMS_LOB.FREETEMPORARY(l_json);
    EXCEPTION
        WHEN OTHERS THEN
            IF UTL_FILE.IS_OPEN(l_file) THEN UTL_FILE.FCLOSE(l_file); END IF;
            IF l_json IS NOT NULL AND DBMS_LOB.ISTEMPORARY(l_json)=1 THEN
                DBMS_LOB.FREETEMPORARY(l_json);
            END IF;
            RAISE;
    END;
END pkg_json_io;
/

PROMPT Пакеты PKG_ADMIN_API, PKG_USER_API, PKG_SECURITY_API и PKG_JSON_IO созданы.
