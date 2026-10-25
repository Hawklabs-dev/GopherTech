
import sqlite3
from contextlib import closing
from pathlib import Path

DATABASE = Path(__file__).parent / "gophertech.db"


def initialize_database():
    with closing(sqlite3.connect(DATABASE)) as connection:
        connection.execute("""
            CREATE TABLE IF NOT EXISTS equipment (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                manufacturer TEXT,
                model TEXT,
                notes TEXT
            )
        """)
        connection.execute("""
            CREATE TABLE IF NOT EXISTS equipment_loans (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                equipment_id INTEGER NOT NULL REFERENCES equipment(id),
                borrower TEXT NOT NULL CHECK(length(trim(borrower)) > 0),
                checked_out_at TEXT NOT NULL,
                returned_at TEXT
            )
        """)
        connection.execute("""
            CREATE UNIQUE INDEX IF NOT EXISTS one_active_loan_per_equipment
            ON equipment_loans(equipment_id) WHERE returned_at IS NULL
        """)
        from finance import initialize_finance
        initialize_finance(connection)
        from jobs import initialize_jobs
        initialize_jobs(connection)
        connection.commit()


if __name__ == "__main__":
    initialize_database()
    print("GopherTech database initialized!")
