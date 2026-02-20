#!/usr/bin/env python3
import argparse
import getpass
import json
import select
import signal
import sys
import time
from datetime import datetime

import psycopg2
import psycopg2.extensions


def clear_screen():
    # ANSI-Bildschirm löschen
    sys.stdout.write('\x1b[2J\x1b[H')
    sys.stdout.flush()


def move_cursor(line, col):
    sys.stdout.write(f'\x1b[{line};{col}H')


def print_at(line, col, text):
    move_cursor(line, col)
    sys.stdout.write(text)
    sys.stdout.flush()


def render_board(board_str):
    # board_str erwartete Länge 9, Zeichen wie 'X', 'O', '-'
    cells = [c if c != '-' else ' ' for c in board_str]
    lines = []
    lines.append(f" {cells[0]} | {cells[1]} | {cells[2]} ")
    lines.append("---+---+---")
    lines.append(f" {cells[3]} | {cells[4]} | {cells[5]} ")
    lines.append("---+---+---")
    lines.append(f" {cells[6]} | {cells[7]} | {cells[8]} ")
    return '\n'.join(lines)


class TTTListener:
    def __init__(self, dsn):
        self.dsn = dsn
        self.conn = None
        self.boards = {}  # game_id -> board_str
        self.last_update = None
        self.last_game_id = None
        self.stats = {
            'x_wins': 0,
            'o_wins': 0,
            'draws': 0,
            'total_games': 0,
        }
        self._initial_drawn = False
        # Layout-Positionen (1-basierte Terminalzeilen)
        self._line_header = 1
        self._line_updated = 2
        self._line_gameid = 4
        self._line_board_top = 5
        self._line_stats_top = 11

    def connect(self):
        self.conn = psycopg2.connect(self.dsn)
        self.conn.set_isolation_level(psycopg2.extensions.ISOLATION_LEVEL_AUTOCOMMIT)
        cur = self.conn.cursor()
        cur.execute("LISTEN tictactoe_board;")
        cur.execute("LISTEN tictactoe_stats;")
        cur.close()

    def close(self):
        if self.conn:
            try:
                cur = self.conn.cursor()
                cur.execute("UNLISTEN *;")
                cur.close()
            except Exception:
                pass
            try:
                self.conn.close()
            except Exception:
                pass

    def handle_board(self, payload):
        try:
            data = json.loads(payload)
        except Exception:
            return
        game_id = data.get('game_id')
        board = data.get('board')
        if game_id is None or board is None:
            return
        # normalize board to length 9
        if isinstance(board, list):
            board_str = ''.join(board)
        else:
            board_str = str(board)
        if len(board_str) != 9:
            # ungültig ignorieren
            return
        prev = self.boards.get(game_id)
        self.boards[game_id] = board_str
        self.last_update = datetime.now()
        self.last_game_id = game_id
        # einmal vorab zeichnen
        if not self._initial_drawn:
            self.initial_draw()
        # nur geänderte Zellen für dieses Spiel aktualisieren
        if prev is None:
            prev = ' ' * 9
        self.update_board_cells(prev, board_str)

    def handle_stats(self, payload):
        try:
            data = json.loads(payload)
        except Exception:
            return
        # bekannte Statistik-Schlüssel aktualisieren
        for k in ('x_wins', 'o_wins', 'draws', 'total_games'):
            if k in data:
                # sicherstellen, dass int
                try:
                    self.stats[k] = int(data[k])
                except Exception:
                    pass
        # nur Statistikbereich aktualisieren
        self.redraw_stats()

    def initial_draw(self):
        # Vollständige statische Layout-Zeichnung
        clear_screen()
        print('Tic-Tac-Toe Listener (receiving notifications)')
        print('Updated:', self.last_update.isoformat() if self.last_update else 'never')
        print()
        print('Game ID:')
        # statische Brett-Vorlage (3 Zeilen mit Trennlinien)
        print('   |   |   ')
        print('---+---+---')
        print('   |   |   ')
        print('---+---+---')
        print('   |   |   ')
        print()
        print('Statistics:')
        print(f" X wins : {self.stats.get('x_wins', 0)}")
        print(f" O wins : {self.stats.get('o_wins', 0)}")
        print(f" Draws  : {self.stats.get('draws', 0)}")
        print(f" Total  : {self.stats.get('total_games', 0)}")
        print('\n(Press Ctrl+C to exit)')
        sys.stdout.flush()
        self._initial_drawn = True

    def update_board_cells(self, prev_board, new_board):
        """Nur geänderte Zellen auf dem statischen Brett aktualisieren."""
        base_line = self._line_board_top
        # cell columns: 1-based column positions for cells are 2,6,10
        base_col = 2
        for i in range(9):
            prev_c = prev_board[i] if i < len(prev_board) else ' '
            new_c = new_board[i] if i < len(new_board) else ' '
            prev_chr = prev_c if prev_c != '-' else ' '
            new_chr = new_c if new_c != '-' else ' '
            if prev_chr != new_chr:
                r = i // 3
                c = i % 3
                line = base_line + r * 2
                col = base_col + c * 4
                print_at(line, col, new_chr)
        # update Game ID and stats timestamp
        print_at(self._line_gameid, 1, f'Game ID: {self.last_game_id}   ')
        self.redraw_stats()

    def redraw_stats(self):
        # update updated timestamp and stats lines
        print_at(self._line_updated, 1, 'Updated: ' + (self.last_update.isoformat() if self.last_update else 'never'))
        print_at(self._line_stats_top + 1, 1, f" X wins : {self.stats.get('x_wins', 0)}")
        print_at(self._line_stats_top + 2, 1, f" O wins : {self.stats.get('o_wins', 0)}")
        print_at(self._line_stats_top + 3, 1, f" Draws  : {self.stats.get('draws', 0)}")
        print_at(self._line_stats_top + 4, 1, f" Total  : {self.stats.get('total_games', 0)}")

    def loop(self):
        if self.conn is None:
            self.connect()
        print('Listening for notifications on channels: tictactoe_board, tictactoe_stats')
        try:
            while True:
                if select.select([self.conn], [], [], 10) == ([], [], []):
                    if not self._initial_drawn:
                        self.initial_draw()
                    else:
                        self.redraw()
                    continue
                self.conn.poll()
                while self.conn.notifies:
                    notify = self.conn.notifies.pop(0)
                    if notify.channel == 'tictactoe_board':
                        self.handle_board(notify.payload)
                    elif notify.channel == 'tictactoe_stats':
                        self.handle_stats(notify.payload)
        except KeyboardInterrupt:
            print('\nInterrupted, exiting...')
        finally:
            self.close()

    def redraw(self):
        # sanfte vollständige Neuzeichnung (für Heartbeat verwendet)
        if not self._initial_drawn:
            self.initial_draw()
            return
        # Zeitstempel aktualisieren
        print_at(self._line_updated, 1, 'Updated: ' + (self.last_update.isoformat() if self.last_update else 'never'))
        # aktuelles Brett vollständig neuzeichnen
        if self.last_game_id is not None:
            board_str = self.boards.get(self.last_game_id, ' ' * 9)
            rows = render_board(board_str).splitlines()
            for idx, line in enumerate(rows):
                print_at(self._line_board_top + idx, 1, line)
            print_at(self._line_gameid, 1, f'Game ID: {self.last_game_id}   ')
        # Statistiken
        self.redraw_stats()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--host', default='localhost')
    parser.add_argument('--port', default='5432')
    parser.add_argument('--dbname', default='postgres')
    parser.add_argument('--user', default='postgres')
    parser.add_argument('--password', default=None)
    args = parser.parse_args()

    pwd = args.password
    if pwd is None:
        try:
            pwd = getpass.getpass('DB password (leave empty for none): ')
        except Exception:
            pwd = None
    dsn = f"dbname={args.dbname} user={args.user} host={args.host} port={args.port}"
    if pwd:
        dsn += f" password={pwd}"

    listener = TTTListener(dsn)
    # SIGTERM graceful behandeln
    signal.signal(signal.SIGTERM, lambda signum, frame: sys.exit(0))
    listener.loop()


if __name__ == '__main__':
    main()
