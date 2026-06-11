CREATE OR REPLACE FUNCTION public.notify_statistics(
	)
    RETURNS void
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
BEGIN
    PERFORM pg_notify('tictactoe_stats', 
        (SELECT JSON_BUILD_OBJECT('x_wins', x_wins, 'o_wins', o_wins, 'draws', draws, 'total_games', total_games)::TEXT FROM statistics WHERE stat_id = 1));
END;
$BODY$;


CREATE OR REPLACE FUNCTION public.check_winner(
	board text)
    RETURNS character
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
BEGIN
    -- Check rows, columns, diagonals
    IF (SUBSTRING(board, 1, 1) = SUBSTRING(board, 2, 1) AND SUBSTRING(board, 2, 1) = SUBSTRING(board, 3, 1) AND SUBSTRING(board, 1, 1) != '-') THEN RETURN SUBSTRING(board, 1, 1); END IF;
    IF (SUBSTRING(board, 4, 1) = SUBSTRING(board, 5, 1) AND SUBSTRING(board, 5, 1) = SUBSTRING(board, 6, 1) AND SUBSTRING(board, 4, 1) != '-') THEN RETURN SUBSTRING(board, 4, 1); END IF;
    IF (SUBSTRING(board, 7, 1) = SUBSTRING(board, 8, 1) AND SUBSTRING(board, 8, 1) = SUBSTRING(board, 9, 1) AND SUBSTRING(board, 7, 1) != '-') THEN RETURN SUBSTRING(board, 7, 1); END IF;
    IF (SUBSTRING(board, 1, 1) = SUBSTRING(board, 4, 1) AND SUBSTRING(board, 4, 1) = SUBSTRING(board, 7, 1) AND SUBSTRING(board, 1, 1) != '-') THEN RETURN SUBSTRING(board, 1, 1); END IF;
    IF (SUBSTRING(board, 2, 1) = SUBSTRING(board, 5, 1) AND SUBSTRING(board, 5, 1) = SUBSTRING(board, 8, 1) AND SUBSTRING(board, 2, 1) != '-') THEN RETURN SUBSTRING(board, 2, 1); END IF;
    IF (SUBSTRING(board, 3, 1) = SUBSTRING(board, 6, 1) AND SUBSTRING(board, 6, 1) = SUBSTRING(board, 9, 1) AND SUBSTRING(board, 3, 1) != '-') THEN RETURN SUBSTRING(board, 3, 1); END IF;
    IF (SUBSTRING(board, 1, 1) = SUBSTRING(board, 5, 1) AND SUBSTRING(board, 5, 1) = SUBSTRING(board, 9, 1) AND SUBSTRING(board, 1, 1) != '-') THEN RETURN SUBSTRING(board, 1, 1); END IF;
    IF (SUBSTRING(board, 3, 1) = SUBSTRING(board, 5, 1) AND SUBSTRING(board, 5, 1) = SUBSTRING(board, 7, 1) AND SUBSTRING(board, 3, 1) != '-') THEN RETURN SUBSTRING(board, 3, 1); END IF;
    RETURN NULL;
END;
$BODY$;
