-- Erstelle Tabellen für Tic-Tac-Toe-Spiel
CREATE TABLE IF NOT EXISTS game_state (
    game_id SERIAL PRIMARY KEY,
    board TEXT,
    current_player CHAR(1),
    status VARCHAR(20),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS moves (
    move_id SERIAL PRIMARY KEY,
    game_id INT REFERENCES game_state(game_id),
    player CHAR(1),
    position INT,
    move_order INT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS statistics (
    stat_id SERIAL PRIMARY KEY,
    x_wins INT DEFAULT 0,
    o_wins INT DEFAULT 0,
    draws INT DEFAULT 0,
    total_games INT DEFAULT 0
);

-- Initialisiere Statistiken
INSERT INTO statistics DEFAULT VALUES;


CREATE OR REPLACE PROCEDURE public.play_tictactoe_immediate(IN num_games integer)
LANGUAGE plpgsql
AS $procedure$
DECLARE
    game_count INT := 0;
    board TEXT := '---------';
    current_player CHAR(1) := 'X';
    v_game_id INT;
    move_pos INT;
    winner CHAR(1);
    move_count INT;
BEGIN
    WHILE game_count < num_games LOOP
        -- Initialisiere neues Spiel
        board := '---------';
        current_player := 'X';
        move_count := 0;

        INSERT INTO game_state (board, current_player, status)
        VALUES (board, current_player, 'ACTIVE')
        RETURNING game_state.game_id INTO v_game_id;
        -- Commit, damit Listener das neue Spiel sofort sehen
        COMMIT;
        START TRANSACTION;

        -- Spiele Spiel
        WHILE move_count < 9 LOOP
            -- KI wählt zufällige verfügbare Position
            move_pos := (FLOOR(RANDOM() * 9))::INT;

            -- Überprüfe, ob Position frei ist
            WHILE SUBSTRING(board, move_pos + 1, 1) != '-' AND move_count < 9 LOOP
                move_pos := (FLOOR(RANDOM() * 9))::INT;
            END LOOP;

            -- Mache Zug
            board := OVERLAY(board PLACING current_player FROM move_pos + 1 FOR 1);
            move_count := move_count + 1;

            -- Zeichne Zug auf
            INSERT INTO moves (game_id, player, position, move_order)
            VALUES (v_game_id, current_player, move_pos, move_count);

            -- Benachrichtige über Spielbrett-Zustand und commit, damit Listener es jetzt erhalten
            PERFORM pg_notify('tictactoe_board',
                JSON_BUILD_OBJECT('game_id', v_game_id, 'board', board, 'player', current_player)::TEXT);
            COMMIT;
            START TRANSACTION;

            -- Überprüfe Gewinnbedingung
            winner := check_winner(board);
            IF winner IS NOT NULL THEN
                UPDATE game_state SET status = 'FINISHED' WHERE game_id = v_game_id;
                UPDATE statistics SET total_games = total_games + 1 WHERE stat_id = 1;

                IF winner = 'X' THEN
                    UPDATE statistics SET x_wins = x_wins + 1 WHERE stat_id = 1;
                ELSIF winner = 'O' THEN
                    UPDATE statistics SET o_wins = o_wins + 1 WHERE stat_id = 1;
                END IF;

                PERFORM notify_statistics();
                COMMIT;
                START TRANSACTION;
                EXIT;
            END IF;

            -- Überprüfe Unentschieden
            IF move_count = 9 THEN
                UPDATE game_state SET status = 'DRAW' WHERE game_id = v_game_id;
                UPDATE statistics SET draws = draws + 1, total_games = total_games + 1 WHERE stat_id = 1;
                PERFORM notify_statistics();
                COMMIT;
                START TRANSACTION;
            END IF;

            -- Wechsle Spieler
            current_player := CASE WHEN current_player = 'X' THEN 'O' ELSE 'X' END;
        END LOOP;

        game_count := game_count + 1;
    END LOOP;
END;
$procedure$;