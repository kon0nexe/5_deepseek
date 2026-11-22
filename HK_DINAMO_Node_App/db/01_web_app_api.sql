-- ============================================================================
-- Web API gateway for the Dynamo Minsk coursework application.
-- Run as HK_DINAMO in the project's PDB after install_all.sql.
-- The web database account receives EXECUTE on this package only; no table DML.
-- Includes ARENA_SEATS (full 2D arena seat map). Script is idempotent: safe to
-- re-run to upgrade an existing DB; the seat-generation block below uses
-- NOT EXISTS, so re-runs never duplicate seats.
-- ============================================================================
WHENEVER SQLERROR EXIT SQL.SQLCODE
SET ECHO ON
SET DEFINE OFF

CREATE OR REPLACE PACKAGE pkg_web_api AUTHID DEFINER AS
    PROCEDURE has_main_admin(p_exists OUT NUMBER);
    PROCEDURE get_login(p_username IN VARCHAR2, p_user_id OUT NUMBER,
        p_password_hash OUT VARCHAR2, p_email OUT VARCHAR2,
        p_role OUT VARCHAR2, p_is_active OUT CHAR);
    PROCEDURE register_user(p_username IN VARCHAR2, p_password_hash IN VARCHAR2,
        p_email IN VARCHAR2, p_first_name IN VARCHAR2, p_last_name IN VARCHAR2,
        p_city IN VARCHAR2, p_user_id OUT NUMBER);
    PROCEDURE bootstrap_main_admin(p_username IN VARCHAR2, p_password_hash IN VARCHAR2,
        p_email IN VARCHAR2, p_first_name IN VARCHAR2, p_last_name IN VARCHAR2,
        p_city IN VARCHAR2, p_user_id OUT NUMBER);

    PROCEDURE dashboard(p_result OUT SYS_REFCURSOR);
    PROCEDURE list_players(p_result OUT SYS_REFCURSOR);
    PROCEDURE list_matches(p_date_from IN DATE, p_date_to IN DATE,
        p_result OUT SYS_REFCURSOR);
    PROCEDURE match_detail(p_match_id IN NUMBER, p_result OUT SYS_REFCURSOR);
    PROCEDURE list_merch(p_result OUT SYS_REFCURSOR);
    PROCEDURE list_stadiums(p_result OUT SYS_REFCURSOR);
    PROCEDURE list_sectors(p_stadium_id IN NUMBER, p_result OUT SYS_REFCURSOR);
    PROCEDURE list_sector_rows(p_match_id IN NUMBER, p_sector_id IN NUMBER,
        p_result OUT SYS_REFCURSOR);
    PROCEDURE list_seats(p_match_id IN NUMBER, p_sector_id IN NUMBER,
        p_seat_row IN NUMBER, p_result OUT SYS_REFCURSOR);
    PROCEDURE arena_seats(p_match_id IN NUMBER, p_result OUT SYS_REFCURSOR);
    PROCEDURE reserve_ticket(p_ticket_id IN NUMBER, p_app_user_id IN NUMBER,
        p_minutes IN NUMBER DEFAULT 15);
    PROCEDURE purchase_ticket(p_ticket_id IN NUMBER, p_app_user_id IN NUMBER);
    PROCEDURE cancel_reservation(p_ticket_id IN NUMBER, p_app_user_id IN NUMBER);
    PROCEDURE my_tickets(p_app_user_id IN NUMBER, p_result OUT SYS_REFCURSOR);
    PROCEDURE list_favorites(p_app_user_id IN NUMBER, p_result OUT SYS_REFCURSOR);
    PROCEDURE add_favorite(p_app_user_id IN NUMBER, p_player_id IN NUMBER);
    PROCEDURE remove_favorite(p_app_user_id IN NUMBER, p_player_id IN NUMBER);

    PROCEDURE admin_players(p_result OUT SYS_REFCURSOR);
    PROCEDURE admin_matches(p_result OUT SYS_REFCURSOR);
    PROCEDURE admin_tickets(p_match_id IN NUMBER, p_status IN VARCHAR2,
        p_page IN NUMBER, p_page_size IN NUMBER, p_result OUT SYS_REFCURSOR);
    PROCEDURE admin_merch(p_result OUT SYS_REFCURSOR);
    PROCEDURE list_fans(p_result OUT SYS_REFCURSOR);
    PROCEDURE add_player(p_first_name IN VARCHAR2, p_last_name IN VARCHAR2,
        p_position IN VARCHAR2, p_jersey_number IN NUMBER, p_birth_date IN DATE,
        p_country IN VARCHAR2, p_height_cm IN NUMBER, p_weight_kg IN NUMBER,
        p_player_id OUT NUMBER);
    PROCEDURE update_player(p_player_id IN NUMBER, p_first_name IN VARCHAR2,
        p_last_name IN VARCHAR2, p_position IN VARCHAR2, p_jersey_number IN NUMBER,
        p_birth_date IN DATE, p_country IN VARCHAR2, p_height_cm IN NUMBER,
        p_weight_kg IN NUMBER, p_is_active IN CHAR);
    PROCEDURE delete_player(p_player_id IN NUMBER);
    PROCEDURE add_match(p_match_date IN DATE, p_opponent_name IN VARCHAR2,
        p_stadium_id IN NUMBER, p_is_home IN CHAR, p_match_id OUT NUMBER);
    PROCEDURE update_match(p_match_id IN NUMBER, p_match_date IN DATE,
        p_opponent_name IN VARCHAR2, p_stadium_id IN NUMBER, p_is_home IN CHAR,
        p_match_status IN VARCHAR2, p_goals_for IN NUMBER, p_goals_against IN NUMBER);
    PROCEDURE delete_match(p_match_id IN NUMBER);
    PROCEDURE add_ticket(p_match_id IN NUMBER, p_sector_id IN NUMBER,
        p_seat_row IN NUMBER, p_seat_number IN NUMBER, p_price IN NUMBER,
        p_ticket_id OUT NUMBER);
    PROCEDURE update_ticket(p_ticket_id IN NUMBER, p_seat_row IN NUMBER,
        p_seat_number IN NUMBER, p_price IN NUMBER);
    PROCEDURE delete_ticket(p_ticket_id IN NUMBER);
    PROCEDURE sell_ticket(p_ticket_id IN NUMBER, p_fan_id IN NUMBER);
    PROCEDURE return_ticket(p_ticket_id IN NUMBER);
    PROCEDURE release_expired(p_released_count OUT NUMBER);
    PROCEDURE add_merch(p_name IN VARCHAR2, p_category IN VARCHAR2,
        p_price IN NUMBER, p_description IN VARCHAR2, p_merch_id OUT NUMBER);
    PROCEDURE update_merch(p_merch_id IN NUMBER, p_name IN VARCHAR2,
        p_category IN VARCHAR2, p_price IN NUMBER, p_description IN VARCHAR2,
        p_is_active IN CHAR);
    PROCEDURE delete_merch(p_merch_id IN NUMBER);

    PROCEDURE app_users(p_result OUT SYS_REFCURSOR);
    PROCEDURE change_user_role(p_user_id IN NUMBER, p_role IN VARCHAR2);
    PROCEDURE set_user_active(p_user_id IN NUMBER, p_is_active IN CHAR);

    PROCEDURE olap_summary(p_date_from IN DATE, p_date_to IN DATE,
        p_sold_count OUT NUMBER, p_revenue OUT NUMBER, p_merch_revenue OUT NUMBER);
    PROCEDURE olap_sales_rollup(p_date_from IN DATE, p_date_to IN DATE,
        p_result OUT SYS_REFCURSOR);
    PROCEDURE olap_sales_cube(p_date_from IN DATE, p_date_to IN DATE,
        p_result OUT SYS_REFCURSOR);
    PROCEDURE olap_players(p_result OUT SYS_REFCURSOR);
    PROCEDURE import_players_json(p_json IN CLOB, p_inserted OUT NUMBER);
    PROCEDURE export_players_json(p_json OUT CLOB);
END pkg_web_api;
/

CREATE OR REPLACE PACKAGE BODY pkg_web_api AS
    PROCEDURE has_main_admin(p_exists OUT NUMBER) IS
    BEGIN
        SELECT CASE WHEN COUNT(*)=0 THEN 0 ELSE 1 END
          INTO p_exists FROM app_users WHERE role='MAIN_ADMIN';
    END;

    PROCEDURE get_login(p_username IN VARCHAR2, p_user_id OUT NUMBER,
        p_password_hash OUT VARCHAR2, p_email OUT VARCHAR2,
        p_role OUT VARCHAR2, p_is_active OUT CHAR) IS
    BEGIN
        p_user_id := NULL; p_password_hash := NULL; p_email := NULL;
        p_role := NULL; p_is_active := 'N';
        SELECT user_id, password_hash, email, role, is_active
          INTO p_user_id, p_password_hash, p_email, p_role, p_is_active
          FROM app_users WHERE LOWER(username)=LOWER(TRIM(p_username));
    EXCEPTION WHEN NO_DATA_FOUND THEN NULL;
    END;

    PROCEDURE register_user(p_username IN VARCHAR2, p_password_hash IN VARCHAR2,
        p_email IN VARCHAR2, p_first_name IN VARCHAR2, p_last_name IN VARCHAR2,
        p_city IN VARCHAR2, p_user_id OUT NUMBER) IS
        l_fan_id NUMBER;
    BEGIN
        INSERT INTO dim_fan(first_name,last_name,email,city)
        VALUES(TRIM(p_first_name),TRIM(p_last_name),LOWER(TRIM(p_email)),p_city)
        RETURNING fan_id INTO l_fan_id;
        pkg_security_api.create_app_user(TRIM(p_username),p_password_hash,
            LOWER(TRIM(p_email)),'USER',l_fan_id,p_user_id);
    END;

    PROCEDURE bootstrap_main_admin(p_username IN VARCHAR2, p_password_hash IN VARCHAR2,
        p_email IN VARCHAR2, p_first_name IN VARCHAR2, p_last_name IN VARCHAR2,
        p_city IN VARCHAR2, p_user_id OUT NUMBER) IS
        l_count NUMBER;
        l_fan_id NUMBER;
    BEGIN
        SELECT COUNT(*) INTO l_count FROM app_users WHERE role='MAIN_ADMIN';
        IF l_count > 0 THEN
            RAISE_APPLICATION_ERROR(-20110,'Главный администратор уже создан.');
        END IF;
        INSERT INTO dim_fan(first_name,last_name,email,city)
        VALUES(TRIM(p_first_name),TRIM(p_last_name),LOWER(TRIM(p_email)),p_city)
        RETURNING fan_id INTO l_fan_id;
        pkg_security_api.create_app_user(TRIM(p_username),p_password_hash,
            LOWER(TRIM(p_email)),'MAIN_ADMIN',l_fan_id,p_user_id);
    END;

    PROCEDURE dashboard(p_result OUT SYS_REFCURSOR) IS
    BEGIN
        OPEN p_result FOR
            SELECT (SELECT COUNT(*) FROM dim_player WHERE is_active='Y') AS players_count,
                   (SELECT COUNT(*) FROM dim_match WHERE match_status='SCHEDULED'
                      AND match_date>=TRUNC(SYSDATE)
                      AND opponent_name NOT LIKE 'TEST PERF %') AS upcoming_matches,
                   (SELECT COUNT(*) FROM tickets WHERE status='SOLD') AS sold_tickets,
                   (SELECT NVL(SUM(price),0) FROM tickets WHERE status='SOLD') AS ticket_revenue,
                   (SELECT COUNT(*) FROM app_users WHERE is_active='Y') AS active_users
              FROM dual;
    END;

    PROCEDURE list_players(p_result OUT SYS_REFCURSOR) IS
    BEGIN
        OPEN p_result FOR
            SELECT p.player_id,p.first_name,p.last_name,p.position,p.jersey_number,
                   p.birth_date,p.country,p.height_cm,p.weight_kg,
                   NVL(f.fans_favorited,0) AS fans_favorited,
                   NVL(s.goals_total,0) AS goals_total,
                   NVL(s.assists_total,0) AS assists_total,
                   NVL(s.points_total,0) AS points_total
              FROM dim_player p
              LEFT JOIN v_player_popularity f ON f.player_id=p.player_id
              LEFT JOIN v_player_performance s ON s.player_id=p.player_id
             WHERE p.is_active='Y'
             ORDER BY p.last_name,p.first_name;
    END;

    PROCEDURE list_matches(p_date_from IN DATE, p_date_to IN DATE,
        p_result OUT SYS_REFCURSOR) IS
    BEGIN
        OPEN p_result FOR
            SELECT m.match_id,m.match_date,m.opponent_name,m.stadium_id,
                   st.name AS stadium,st.city,m.is_home,m.goals_for,m.goals_against,
                   m.match_status,
                   (SELECT COUNT(*) FROM tickets t WHERE t.match_id=m.match_id
                      AND (t.status IN ('FREE','RETURNED') OR (t.status='RESERVED' AND t.reserved_until<=SYSDATE)))
                      AS available_tickets
              FROM dim_match m JOIN dim_stadium st ON st.stadium_id=m.stadium_id
             WHERE m.opponent_name NOT LIKE 'TEST PERF %'
               AND (p_date_from IS NULL OR m.match_date>=TRUNC(p_date_from))
               AND (p_date_to IS NULL OR m.match_date<TRUNC(p_date_to)+1)
             ORDER BY m.match_date;
    END;

    PROCEDURE match_detail(p_match_id IN NUMBER, p_result OUT SYS_REFCURSOR) IS
    BEGIN
        OPEN p_result FOR
            SELECT m.match_id,m.match_date,m.opponent_name,m.stadium_id,
                   st.name AS stadium,st.city,st.capacity,m.is_home,
                   m.goals_for,m.goals_against,m.match_status
              FROM dim_match m JOIN dim_stadium st ON st.stadium_id=m.stadium_id
             WHERE m.match_id=p_match_id AND m.opponent_name NOT LIKE 'TEST PERF %';
    END;

    PROCEDURE list_merch(p_result OUT SYS_REFCURSOR) IS
    BEGIN
        OPEN p_result FOR
            SELECT merch_id,name,category,price,description
              FROM dim_merch WHERE is_active='Y' ORDER BY category,name;
    END;

    PROCEDURE list_stadiums(p_result OUT SYS_REFCURSOR) IS
    BEGIN
        OPEN p_result FOR SELECT stadium_id,name,city,capacity FROM dim_stadium ORDER BY name;
    END;

    PROCEDURE list_sectors(p_stadium_id IN NUMBER, p_result OUT SYS_REFCURSOR) IS
    BEGIN
        OPEN p_result FOR
            SELECT sector_id,stadium_id,sector_code,category,capacity
              FROM dim_sector WHERE stadium_id=p_stadium_id ORDER BY sector_code;
    END;

    PROCEDURE list_sector_rows(p_match_id IN NUMBER, p_sector_id IN NUMBER,
        p_result OUT SYS_REFCURSOR) IS
    BEGIN
        OPEN p_result FOR
            SELECT seat_row,COUNT(*) AS seats_total,
                   SUM(CASE WHEN status IN ('FREE','RETURNED') OR
                      (status='RESERVED' AND reserved_until<=SYSDATE) THEN 1 ELSE 0 END) AS seats_free
              FROM tickets WHERE match_id=p_match_id AND sector_id=p_sector_id
             GROUP BY seat_row ORDER BY seat_row;
    END;

    PROCEDURE list_seats(p_match_id IN NUMBER, p_sector_id IN NUMBER,
        p_seat_row IN NUMBER, p_result OUT SYS_REFCURSOR) IS
    BEGIN
        OPEN p_result FOR
            SELECT ticket_id,match_id,sector_id,seat_row,seat_number,price,
                   CASE WHEN status='RESERVED' AND reserved_until<=SYSDATE
                        THEN 'FREE' ELSE status END AS status,
                   CASE WHEN status='RESERVED' AND reserved_until>SYSDATE
                        THEN reserved_until END AS reserved_until
              FROM tickets
             WHERE match_id=p_match_id AND sector_id=p_sector_id AND seat_row=p_seat_row
             ORDER BY seat_number;
    END;

    PROCEDURE arena_seats(p_match_id IN NUMBER, p_result OUT SYS_REFCURSOR) IS
    BEGIN
        OPEN p_result FOR
            SELECT t.ticket_id, t.sector_id, s.sector_code, s.category,
                   t.seat_row, t.seat_number, t.price,
                   CASE WHEN t.status='RESERVED' AND t.reserved_until<=SYSDATE
                        THEN 'FREE' ELSE t.status END AS status
              FROM tickets t JOIN dim_sector s ON s.sector_id=t.sector_id
             WHERE t.match_id=p_match_id
             ORDER BY s.sector_code, t.seat_row, t.seat_number;
    END;

    PROCEDURE reserve_ticket(p_ticket_id IN NUMBER, p_app_user_id IN NUMBER,
        p_minutes IN NUMBER DEFAULT 15) IS
        l_fan_id NUMBER; l_status VARCHAR2(10); l_until DATE;
    BEGIN
        IF p_minutes IS NULL OR p_minutes<1 OR p_minutes>120 THEN
            RAISE_APPLICATION_ERROR(-20120,'Срок резерва должен быть от 1 до 120 минут.');
        END IF;
        SELECT fan_id INTO l_fan_id FROM app_users
         WHERE user_id=p_app_user_id AND is_active='Y' AND fan_id IS NOT NULL;
        SELECT status,reserved_until INTO l_status,l_until FROM tickets
         WHERE ticket_id=p_ticket_id FOR UPDATE;
        IF l_status='RESERVED' AND l_until<=SYSDATE THEN
            UPDATE tickets SET status='FREE',reserved_by=NULL,reserved_until=NULL
             WHERE ticket_id=p_ticket_id;
            l_status:='FREE';
        END IF;
        IF l_status NOT IN ('FREE','RETURNED') THEN
            RAISE_APPLICATION_ERROR(-20121,'Это место уже занято или зарезервировано.');
        END IF;
        UPDATE tickets SET status='RESERVED',fan_id=NULL,sale_time_id=NULL,
            reserved_by=l_fan_id,reserved_until=SYSDATE+(p_minutes/1440)
         WHERE ticket_id=p_ticket_id;
    EXCEPTION WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20122,'Пользователь или билет не найден.');
    END;

    PROCEDURE purchase_ticket(p_ticket_id IN NUMBER, p_app_user_id IN NUMBER) IS
        l_fan_id NUMBER; l_reserved_by NUMBER; l_until DATE; l_status VARCHAR2(10);
        l_time_id NUMBER(8);
    BEGIN
        SELECT fan_id INTO l_fan_id FROM app_users
         WHERE user_id=p_app_user_id AND is_active='Y' AND fan_id IS NOT NULL;
        SELECT status,reserved_by,reserved_until INTO l_status,l_reserved_by,l_until
          FROM tickets WHERE ticket_id=p_ticket_id FOR UPDATE;
        IF l_status<>'RESERVED' OR l_reserved_by<>l_fan_id OR l_until<=SYSDATE THEN
            RAISE_APPLICATION_ERROR(-20123,'Резерв истёк или билет зарезервирован другим пользователем.');
        END IF;
        SELECT time_id INTO l_time_id FROM dim_time WHERE full_date=TRUNC(SYSDATE);
        UPDATE tickets SET status='SOLD',fan_id=l_fan_id,sale_time_id=l_time_id,
            reserved_by=NULL,reserved_until=NULL WHERE ticket_id=p_ticket_id;
    EXCEPTION WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20124,'Не найден пользователь, билет или календарная дата.');
    END;

    PROCEDURE cancel_reservation(p_ticket_id IN NUMBER, p_app_user_id IN NUMBER) IS
        l_fan_id NUMBER; l_reserved_by NUMBER; l_status VARCHAR2(10);
    BEGIN
        SELECT fan_id INTO l_fan_id FROM app_users
         WHERE user_id=p_app_user_id AND is_active='Y' AND fan_id IS NOT NULL;
        SELECT status,reserved_by INTO l_status,l_reserved_by FROM tickets
         WHERE ticket_id=p_ticket_id FOR UPDATE;
        IF l_status<>'RESERVED' OR l_reserved_by<>l_fan_id THEN
            RAISE_APPLICATION_ERROR(-20125,'Резерв не принадлежит текущему пользователю.');
        END IF;
        UPDATE tickets SET status='FREE',reserved_by=NULL,reserved_until=NULL
         WHERE ticket_id=p_ticket_id;
    EXCEPTION WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20124,'Не найден пользователь или билет.');
    END;

    PROCEDURE my_tickets(p_app_user_id IN NUMBER, p_result OUT SYS_REFCURSOR) IS
        l_fan_id NUMBER;
    BEGIN
        SELECT fan_id INTO l_fan_id FROM app_users
         WHERE user_id=p_app_user_id AND is_active='Y' AND fan_id IS NOT NULL;
        OPEN p_result FOR
            SELECT t.ticket_id,t.status,t.price,t.seat_row,t.seat_number,
                   s.sector_code,m.match_id,m.match_date,m.opponent_name,
                   CASE WHEN t.status='RESERVED' THEN t.reserved_until END AS reserved_until
              FROM tickets t JOIN dim_sector s ON s.sector_id=t.sector_id
              JOIN dim_match m ON m.match_id=t.match_id
             WHERE (t.fan_id=l_fan_id AND t.status IN ('SOLD','RETURNED'))
                OR (t.reserved_by=l_fan_id AND t.status='RESERVED')
             ORDER BY m.match_date DESC,t.ticket_id DESC;
    END;

    PROCEDURE list_favorites(p_app_user_id IN NUMBER, p_result OUT SYS_REFCURSOR) IS
        l_fan_id NUMBER;
    BEGIN
        SELECT fan_id INTO l_fan_id FROM app_users
         WHERE user_id=p_app_user_id AND is_active='Y' AND fan_id IS NOT NULL;
        OPEN p_result FOR
            SELECT p.player_id,p.first_name,p.last_name,p.position,f.created_at
              FROM fan_player_favorites f JOIN dim_player p ON p.player_id=f.player_id
             WHERE f.fan_id=l_fan_id ORDER BY f.created_at DESC;
    END;

    PROCEDURE add_favorite(p_app_user_id IN NUMBER, p_player_id IN NUMBER) IS
        l_fan_id NUMBER;
    BEGIN
        SELECT fan_id INTO l_fan_id FROM app_users
         WHERE user_id=p_app_user_id AND is_active='Y' AND fan_id IS NOT NULL;
        INSERT INTO fan_player_favorites(fan_id,player_id) VALUES(l_fan_id,p_player_id);
    EXCEPTION WHEN DUP_VAL_ON_INDEX THEN
        RAISE_APPLICATION_ERROR(-20126,'Игрок уже добавлен в избранное.');
    END;

    PROCEDURE remove_favorite(p_app_user_id IN NUMBER, p_player_id IN NUMBER) IS
        l_fan_id NUMBER;
    BEGIN
        SELECT fan_id INTO l_fan_id FROM app_users
         WHERE user_id=p_app_user_id AND is_active='Y' AND fan_id IS NOT NULL;
        DELETE FROM fan_player_favorites WHERE fan_id=l_fan_id AND player_id=p_player_id;
        IF SQL%ROWCOUNT=0 THEN RAISE_APPLICATION_ERROR(-20127,'Игрок не найден в избранном.'); END IF;
    END;

    PROCEDURE admin_players(p_result OUT SYS_REFCURSOR) IS
    BEGIN
        OPEN p_result FOR
            SELECT player_id,first_name,last_name,position,jersey_number,birth_date,
                   country,height_cm,weight_kg,is_active FROM dim_player
             ORDER BY last_name,first_name;
    END;

    PROCEDURE admin_matches(p_result OUT SYS_REFCURSOR) IS
    BEGIN
        OPEN p_result FOR
            SELECT m.match_id,m.match_date,m.opponent_name,m.stadium_id,st.name AS stadium,
                   m.is_home,m.match_status,m.goals_for,m.goals_against
              FROM dim_match m JOIN dim_stadium st ON st.stadium_id=m.stadium_id
             ORDER BY m.match_date DESC;
    END;

    PROCEDURE admin_tickets(p_match_id IN NUMBER, p_status IN VARCHAR2,
        p_page IN NUMBER, p_page_size IN NUMBER, p_result OUT SYS_REFCURSOR) IS
        l_page NUMBER:=GREATEST(NVL(p_page,1),1);
        l_size NUMBER:=LEAST(GREATEST(NVL(p_page_size,50),1),200);
    BEGIN
        OPEN p_result FOR
            SELECT * FROM (
                SELECT ROW_NUMBER() OVER(ORDER BY t.ticket_id DESC) rn,
                       t.ticket_id,t.sector_id,m.match_id,m.match_date,m.opponent_name,
                       s.sector_code,t.seat_row,t.seat_number,t.price,t.status,
                       t.reserved_until,t.fan_id,t.reserved_by
                  FROM tickets t JOIN dim_match m ON m.match_id=t.match_id
                  JOIN dim_sector s ON s.sector_id=t.sector_id
                 WHERE (p_match_id IS NULL OR t.match_id=p_match_id)
                   AND (p_status IS NULL OR t.status=UPPER(p_status))
            ) WHERE rn BETWEEN ((l_page-1)*l_size+1) AND (l_page*l_size)
             ORDER BY rn;
    END;

    PROCEDURE admin_merch(p_result OUT SYS_REFCURSOR) IS
    BEGIN
        OPEN p_result FOR SELECT merch_id,name,category,price,description,is_active
          FROM dim_merch ORDER BY category,name;
    END;

    PROCEDURE list_fans(p_result OUT SYS_REFCURSOR) IS
    BEGIN
        OPEN p_result FOR SELECT fan_id,first_name,last_name,email FROM dim_fan ORDER BY last_name,first_name;
    END;

    PROCEDURE add_player(p_first_name IN VARCHAR2, p_last_name IN VARCHAR2,
        p_position IN VARCHAR2, p_jersey_number IN NUMBER, p_birth_date IN DATE,
        p_country IN VARCHAR2, p_height_cm IN NUMBER, p_weight_kg IN NUMBER,
        p_player_id OUT NUMBER) IS
    BEGIN
        pkg_admin_api.add_player(p_first_name,p_last_name,p_position,p_jersey_number,
            p_birth_date,p_country,p_height_cm,p_weight_kg,p_player_id);
    END;

    PROCEDURE update_player(p_player_id IN NUMBER, p_first_name IN VARCHAR2,
        p_last_name IN VARCHAR2, p_position IN VARCHAR2, p_jersey_number IN NUMBER,
        p_birth_date IN DATE, p_country IN VARCHAR2, p_height_cm IN NUMBER,
        p_weight_kg IN NUMBER, p_is_active IN CHAR) IS
    BEGIN
        pkg_admin_api.update_player(p_player_id,p_first_name,p_last_name,p_position,
            p_jersey_number,p_birth_date,p_country,p_height_cm,p_weight_kg,p_is_active);
    END;

    PROCEDURE delete_player(p_player_id IN NUMBER) IS
    BEGIN pkg_admin_api.delete_player(p_player_id); END;

    PROCEDURE add_match(p_match_date IN DATE, p_opponent_name IN VARCHAR2,
        p_stadium_id IN NUMBER, p_is_home IN CHAR, p_match_id OUT NUMBER) IS
    BEGIN pkg_admin_api.add_match(p_match_date,p_opponent_name,p_stadium_id,p_is_home,p_match_id); END;

    PROCEDURE update_match(p_match_id IN NUMBER, p_match_date IN DATE,
        p_opponent_name IN VARCHAR2, p_stadium_id IN NUMBER, p_is_home IN CHAR,
        p_match_status IN VARCHAR2, p_goals_for IN NUMBER, p_goals_against IN NUMBER) IS
    BEGIN
        pkg_admin_api.update_match(p_match_id,p_match_date,p_opponent_name,p_stadium_id,
            p_is_home,p_match_status,p_goals_for,p_goals_against);
    END;

    PROCEDURE delete_match(p_match_id IN NUMBER) IS
    BEGIN pkg_admin_api.delete_match(p_match_id); END;

    PROCEDURE add_ticket(p_match_id IN NUMBER, p_sector_id IN NUMBER,
        p_seat_row IN NUMBER, p_seat_number IN NUMBER, p_price IN NUMBER,
        p_ticket_id OUT NUMBER) IS
    BEGIN pkg_admin_api.add_ticket(p_match_id,p_sector_id,p_seat_row,p_seat_number,p_price,p_ticket_id); END;

    PROCEDURE update_ticket(p_ticket_id IN NUMBER, p_seat_row IN NUMBER,
        p_seat_number IN NUMBER, p_price IN NUMBER) IS
        l_status VARCHAR2(10);
    BEGIN
        SELECT status INTO l_status FROM tickets WHERE ticket_id=p_ticket_id FOR UPDATE;
        IF l_status NOT IN ('FREE','RETURNED') THEN
            RAISE_APPLICATION_ERROR(-20128,'Редактировать можно только свободный или возвращённый билет.');
        END IF;
        UPDATE tickets SET seat_row=p_seat_row,seat_number=p_seat_number,price=p_price
         WHERE ticket_id=p_ticket_id;
    EXCEPTION WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20129,'Билет не найден.');
    END;

    PROCEDURE delete_ticket(p_ticket_id IN NUMBER) IS
        l_status VARCHAR2(10);
    BEGIN
        SELECT status INTO l_status FROM tickets WHERE ticket_id=p_ticket_id FOR UPDATE;
        IF l_status NOT IN ('FREE','RETURNED') THEN
            RAISE_APPLICATION_ERROR(-20130,'Удалять можно только свободный или возвращённый билет.');
        END IF;
        DELETE FROM tickets WHERE ticket_id=p_ticket_id;
    EXCEPTION WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20129,'Билет не найден.');
    END;

    PROCEDURE sell_ticket(p_ticket_id IN NUMBER, p_fan_id IN NUMBER) IS
    BEGIN pkg_admin_api.sell_ticket(p_ticket_id,p_fan_id); END;
    PROCEDURE return_ticket(p_ticket_id IN NUMBER) IS
    BEGIN pkg_admin_api.return_ticket(p_ticket_id); END;
    PROCEDURE release_expired(p_released_count OUT NUMBER) IS
    BEGIN pkg_admin_api.release_expired_reservations(p_released_count); END;

    PROCEDURE add_merch(p_name IN VARCHAR2, p_category IN VARCHAR2,
        p_price IN NUMBER, p_description IN VARCHAR2, p_merch_id OUT NUMBER) IS
    BEGIN pkg_admin_api.add_merch(p_name,p_category,p_price,p_description,p_merch_id); END;

    PROCEDURE update_merch(p_merch_id IN NUMBER, p_name IN VARCHAR2,
        p_category IN VARCHAR2, p_price IN NUMBER, p_description IN VARCHAR2,
        p_is_active IN CHAR) IS
    BEGIN pkg_admin_api.update_merch(p_merch_id,p_name,p_category,p_price,p_description,p_is_active); END;
    PROCEDURE delete_merch(p_merch_id IN NUMBER) IS
    BEGIN pkg_admin_api.delete_merch(p_merch_id); END;

    PROCEDURE app_users(p_result OUT SYS_REFCURSOR) IS
    BEGIN
        OPEN p_result FOR
            SELECT user_id,username,email,role,is_active,created_at
              FROM app_users ORDER BY created_at DESC,user_id DESC;
    END;
    PROCEDURE change_user_role(p_user_id IN NUMBER, p_role IN VARCHAR2) IS
    BEGIN pkg_security_api.change_app_user_role(p_user_id,p_role); END;
    PROCEDURE set_user_active(p_user_id IN NUMBER, p_is_active IN CHAR) IS
    BEGIN pkg_security_api.set_app_user_active(p_user_id,p_is_active); END;

    PROCEDURE olap_summary(p_date_from IN DATE, p_date_to IN DATE,
        p_sold_count OUT NUMBER, p_revenue OUT NUMBER, p_merch_revenue OUT NUMBER) IS
    BEGIN
        SELECT COUNT(*),NVL(SUM(t.price),0)
          INTO p_sold_count,p_revenue
          FROM tickets t JOIN dim_time d ON d.time_id=t.sale_time_id
         WHERE t.status='SOLD'
           AND (p_date_from IS NULL OR d.full_date>=TRUNC(p_date_from))
           AND (p_date_to IS NULL OR d.full_date<TRUNC(p_date_to)+1);
        SELECT NVL(SUM(o.total_amount),0) INTO p_merch_revenue
          FROM merch_orders o JOIN dim_time d ON d.time_id=o.time_id
         WHERE o.status='COMPLETED'
           AND (p_date_from IS NULL OR d.full_date>=TRUNC(p_date_from))
           AND (p_date_to IS NULL OR d.full_date<TRUNC(p_date_to)+1);
    END;

    PROCEDURE olap_sales_rollup(p_date_from IN DATE, p_date_to IN DATE,
        p_result OUT SYS_REFCURSOR) IS
    BEGIN
        OPEN p_result FOR
            SELECT CASE
                     WHEN GROUPING(d.season)=1 THEN 'ВСЕГО'
                     WHEN GROUPING(d.year_num)=1 THEN 'Сезон '||d.season
                     WHEN GROUPING(d.month_num)=1 THEN TO_CHAR(d.year_num)||' год — всего'
                     ELSE TO_CHAR(d.year_num)||'-'||LPAD(d.month_num,2,'0')||' / '||TRIM(d.month_name)
                   END AS period_label,
                   GROUPING_ID(d.season,d.year_num,d.month_num,d.month_name) AS grouping_level,
                   COUNT(*) AS tickets_sold,NVL(SUM(t.price),0) AS revenue
              FROM tickets t JOIN dim_time d ON d.time_id=t.sale_time_id
             WHERE t.status='SOLD'
               AND (p_date_from IS NULL OR d.full_date>=TRUNC(p_date_from))
               AND (p_date_to IS NULL OR d.full_date<TRUNC(p_date_to)+1)
             GROUP BY ROLLUP(d.season,d.year_num,d.month_num,d.month_name)
             ORDER BY GROUPING_ID(d.season,d.year_num,d.month_num,d.month_name),
                      d.season,d.year_num,d.month_num;
    END;

    PROCEDURE olap_sales_cube(p_date_from IN DATE, p_date_to IN DATE,
        p_result OUT SYS_REFCURSOR) IS
    BEGIN
        OPEN p_result FOR
            SELECT NVL(d.season,'Все сезоны') AS season,
                   NVL(s.category,'Все категории') AS sector_category,
                   GROUPING_ID(d.season,s.category) AS grouping_level,
                   COUNT(*) AS tickets_sold,NVL(SUM(t.price),0) AS revenue
              FROM tickets t JOIN dim_time d ON d.time_id=t.sale_time_id
              JOIN dim_sector s ON s.sector_id=t.sector_id
             WHERE t.status='SOLD'
               AND (p_date_from IS NULL OR d.full_date>=TRUNC(p_date_from))
               AND (p_date_to IS NULL OR d.full_date<TRUNC(p_date_to)+1)
             GROUP BY CUBE(d.season,s.category)
             ORDER BY GROUPING_ID(d.season,s.category),d.season,s.category;
    END;

    PROCEDURE olap_players(p_result OUT SYS_REFCURSOR) IS
    BEGIN
        OPEN p_result FOR
            SELECT p.player_id,p.first_name,p.last_name,p.position,
                   NVL(f.fans_count,0) AS fans_count,
                   NVL(s.matches_count,0) AS matches_count,
                   NVL(s.goals_total,0) AS goals_total,
                   NVL(s.assists_total,0) AS assists_total,
                   NVL(s.points_total,0) AS points_total
              FROM dim_player p
              LEFT JOIN (SELECT player_id,COUNT(DISTINCT fan_id) fans_count
                           FROM fan_player_favorites GROUP BY player_id) f
                ON f.player_id=p.player_id
              LEFT JOIN (SELECT player_id,COUNT(*) matches_count,
                                SUM(goals) goals_total,SUM(assists) assists_total,
                                SUM(points) points_total
                           FROM fact_match_stats GROUP BY player_id) s
                ON s.player_id=p.player_id
             ORDER BY NVL(f.fans_count,0) DESC,NVL(s.points_total,0) DESC,p.last_name;
    END;

    PROCEDURE import_players_json(p_json IN CLOB, p_inserted OUT NUMBER) IS
    BEGIN
        IF p_json IS NULL THEN
            RAISE_APPLICATION_ERROR(-20131,'Пустой JSON-документ.');
        END IF;
        INSERT INTO dim_player(first_name,last_name,position,jersey_number,birth_date,
            country,height_cm,weight_kg)
        SELECT jt.first_name,jt.last_name,UPPER(jt.position),jt.jersey_number,
               CASE WHEN jt.birth_date IS NOT NULL THEN TO_DATE(jt.birth_date,'YYYY-MM-DD') END,
               jt.country,jt.height_cm,jt.weight_kg
          FROM JSON_TABLE(p_json,'$.players[*]' COLUMNS(
               first_name VARCHAR2(50) PATH '$.first_name',
               last_name VARCHAR2(50) PATH '$.last_name',
               position VARCHAR2(15) PATH '$.position',
               jersey_number NUMBER PATH '$.jersey_number' NULL ON ERROR,
               birth_date VARCHAR2(10) PATH '$.birth_date' NULL ON ERROR,
               country VARCHAR2(50) PATH '$.country' NULL ON ERROR,
               height_cm NUMBER PATH '$.height_cm' NULL ON ERROR,
               weight_kg NUMBER PATH '$.weight_kg' NULL ON ERROR)) jt;
        p_inserted:=SQL%ROWCOUNT;
    END;

    PROCEDURE export_players_json(p_json OUT CLOB) IS
    BEGIN
        SELECT JSON_OBJECT('players' VALUE (
                   SELECT JSON_ARRAYAGG(JSON_OBJECT(
                       'player_id' VALUE player_id,'first_name' VALUE first_name,
                       'last_name' VALUE last_name,'position' VALUE position,
                       'jersey_number' VALUE jersey_number,
                       'birth_date' VALUE CASE WHEN birth_date IS NOT NULL THEN TO_CHAR(birth_date,'YYYY-MM-DD') END,
                       'country' VALUE country,'height_cm' VALUE height_cm,
                       'weight_kg' VALUE weight_kg,'is_active' VALUE is_active
                       NULL ON NULL RETURNING CLOB) RETURNING CLOB)
                     FROM dim_player) FORMAT JSON RETURNING CLOB)
          INTO p_json FROM dual;
    END;
END pkg_web_api;
/

SHOW ERRORS PACKAGE pkg_web_api
SHOW ERRORS PACKAGE BODY pkg_web_api

-- Complete the seeded demo match with 10,000 physical seats (2 sectors x 5,000).
-- Existing sample rows are preserved; duplicate seats are skipped.
DECLARE
    l_match_id NUMBER;
    l_sector_a NUMBER;
    l_sector_b NUMBER;
BEGIN
    BEGIN
        SELECT match_id INTO l_match_id FROM dim_match
         WHERE opponent_name=UNISTR('\0414\0435\043C\043E\043D\0441\0442\0440\0430\0446\0438\043E\043D\043D\044B\0439 \0441\043E\043F\0435\0440\043D\0438\043A') AND ROWNUM=1;
        SELECT MIN(sector_id),MAX(sector_id) INTO l_sector_a,l_sector_b
          FROM dim_sector WHERE stadium_id=(SELECT stadium_id FROM dim_match WHERE match_id=l_match_id);
        IF l_sector_a IS NOT NULL AND l_sector_b IS NOT NULL AND l_sector_a<>l_sector_b THEN
            INSERT INTO tickets(match_id,sector_id,seat_row,seat_number,price,status)
            SELECT l_match_id,l_sector_a,CEIL(q.n/100),MOD(q.n-1,100)+1,45,'FREE'
              FROM (SELECT LEVEL n FROM dual CONNECT BY LEVEL<=5000) q
             WHERE NOT EXISTS (SELECT 1 FROM tickets t WHERE t.match_id=l_match_id
                    AND t.sector_id=l_sector_a AND t.seat_row=CEIL(q.n/100)
                    AND t.seat_number=MOD(q.n-1,100)+1);
            INSERT INTO tickets(match_id,sector_id,seat_row,seat_number,price,status)
            SELECT l_match_id,l_sector_b,CEIL(q.n/100),MOD(q.n-1,100)+1,55,'FREE'
              FROM (SELECT LEVEL n FROM dual CONNECT BY LEVEL<=5000) q
             WHERE NOT EXISTS (SELECT 1 FROM tickets t WHERE t.match_id=l_match_id
                    AND t.sector_id=l_sector_b AND t.seat_row=CEIL(q.n/100)
                    AND t.seat_number=MOD(q.n-1,100)+1);
        END IF;
        DBMS_OUTPUT.PUT_LINE('Демонстрационная схема мест подготовлена; MATCH_ID='||l_match_id);
    EXCEPTION WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE('Демо-матч не найден; пропуск генерации 10 000 мест.');
    END;
    COMMIT;
END;
/

PROMPT PKG_WEB_API создан. Следующий шаг: выполнить db/02_create_web_user.sql от SYS в PDB.
