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
 
ALTER FUNCTION public.notify_statistics()
    OWNER TO postgres;
    