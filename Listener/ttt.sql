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


-- PROCEDURE: public.play_tictactoe_immediate(integer)
 
-- DROP PROCEDURE IF EXISTS public.play_tictactoe_immediate(integer);
 
CREATE OR REPLACE PROCEDURE public.play_tictactoe_immediate(
	IN num_games integer)
LANGUAGE 'plpgsql'
AS $BODY$
DECLARE
    v_game_count INT := 0;
    v_board TEXT := '---------';
    v_current_player CHAR(1) := 'X';
    v_game_id INT;
    v_move_pos INT;
    v_winner CHAR(1);
    v_move_count INT;
BEGIN
    WHILE v_game_count < num_games LOOP
        -- Initialize new game
        v_board := '---------';
        v_current_player := 'X';
        v_move_count := 0;
 
        INSERT INTO game_state (board, current_player, status)
        VALUES (v_board, v_current_player, 'ACTIVE')
        RETURNING game_state.game_id INTO v_game_id;
        COMMIT; -- ensure the inserted game is visible and notifyable
 
        -- Play game
        WHILE v_move_count < 9 LOOP
            -- AI picks random available position
            v_move_pos := (FLOOR(RANDOM() * 9))::INT;
 
            -- Check if position is free
            WHILE SUBSTRING(v_board, v_move_pos + 1, 1) != '-' AND v_move_count < 9 LOOP
                v_move_pos := (FLOOR(RANDOM() * 9))::INT;
            END LOOP;
 
            -- Make move
            v_board := OVERLAY(v_board PLACING v_current_player FROM v_move_pos + 1 FOR 1);
            v_move_count := v_move_count + 1;
 
            -- Record move
            INSERT INTO moves (game_id, player, position, move_order)
            VALUES (v_game_id, v_current_player, v_move_pos, v_move_count);
            COMMIT; -- persist the move so other sessions can see it
 
            -- Notify board state (will be delivered to listeners because of COMMIT)
            PERFORM pg_notify('tictactoe_board', 
                JSON_BUILD_OBJECT('game_id', v_game_id, 'board', v_board, 'player', v_current_player)::TEXT);
            COMMIT; -- ensure NOTIFY is delivered
 
            -- Check win condition
            v_winner := check_winner(v_board);
            IF v_winner IS NOT NULL THEN
                UPDATE game_state SET status = 'FINISHED', board = v_board WHERE game_id = v_game_id;
                UPDATE statistics SET total_games = total_games + 1 WHERE stat_id = 1;
 
                IF v_winner = 'X' THEN
                    UPDATE statistics SET x_wins = x_wins + 1 WHERE stat_id = 1;
                ELSIF v_winner = 'O' THEN
                    UPDATE statistics SET o_wins = o_wins + 1 WHERE stat_id = 1;
                END IF;
                COMMIT;
 
                PERFORM notify_statistics();
                COMMIT;
                EXIT;
            END IF;
 
            -- Check draw
            IF v_move_count = 9 THEN
                UPDATE game_state SET status = 'DRAW', board = v_board WHERE game_id = v_game_id;
                UPDATE statistics SET draws = draws + 1, total_games = total_games + 1 WHERE stat_id = 1;
                COMMIT;
 
                PERFORM notify_statistics();
                COMMIT;
            END IF;
 
            -- Switch player
            v_current_player := CASE WHEN v_current_player = 'X' THEN 'O' ELSE 'X' END;
        END LOOP;
 
        v_game_count := v_game_count + 1;
    END LOOP;
END;
$BODY$;
