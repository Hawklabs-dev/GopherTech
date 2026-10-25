
import sqlite3
from contextlib import closing
from fastapi import FastAPI, HTTPException
from database import DATABASE, initialize_database

app = FastAPI(
    title="HawkLabs GopherTech",
    version="0.1.0",
    description="GopherTech local development backend"
)


@app.on_event("startup")
def startup():
    initialize_database()


@app.get("/")
def home():
    return {
        "application": "GopherTech",
        "developer": "HawkLabs",
        "status": "online",
        "version": "0.1.0"
    }


@app.get("/health")
def health():
    return {"status": "healthy"}


@app.get("/equipment")
def list_equipment():
    with closing(sqlite3.connect(DATABASE)) as connection:
        connection.row_factory = sqlite3.Row
        rows = connection.execute(
            "SELECT * FROM equipment ORDER BY id"
        ).fetchall()

    return {"equipment": [dict(row) for row in rows]}


from pydantic import BaseModel, Field
from datetime import datetime, timezone


class EquipmentCreate(BaseModel):
    name: str
    manufacturer: str | None = None
    model: str | None = None
    notes: str | None = None


@app.post("/equipment", status_code=201)
def add_equipment(item: EquipmentCreate):
    with closing(sqlite3.connect(DATABASE)) as connection:
        cursor = connection.execute(
            """
            INSERT INTO equipment
            (name, manufacturer, model, notes)
            VALUES (?, ?, ?, ?)
            """,
            (
                item.name,
                item.manufacturer,
                item.model,
                item.notes
            )
        )
        connection.commit()
        equipment_id = cursor.lastrowid

    return {
        "id": equipment_id,
        "message": "Equipment added successfully"
    }


class EquipmentCheckout(BaseModel):
    borrower: str = Field(min_length=1, max_length=120)


class EquipmentCheckin(BaseModel):
    checkout_id: int = Field(gt=0)


@app.get("/equipment/availability")
def equipment_availability():
    with closing(sqlite3.connect(DATABASE)) as connection:
        connection.row_factory = sqlite3.Row
        rows = connection.execute("""
            SELECT e.*, l.id AS checkout_id, l.borrower, l.checked_out_at,
                   CASE WHEN l.id IS NULL THEN 'available' ELSE 'checked_out' END AS status
            FROM equipment e
            LEFT JOIN equipment_loans l ON l.equipment_id = e.id AND l.returned_at IS NULL
            ORDER BY e.id
        """).fetchall()
    return {"equipment": [dict(row) for row in rows]}


@app.post("/equipment/{equipment_id}/checkout", status_code=201)
def checkout_equipment(equipment_id: int, item: EquipmentCheckout):
    borrower = item.borrower.strip()
    if not borrower:
        raise HTTPException(status_code=422, detail="Enter the name of the person taking this equipment.")
    with closing(sqlite3.connect(DATABASE)) as connection:
        with connection:
            connection.execute("PRAGMA foreign_keys = ON")
            connection.execute("BEGIN IMMEDIATE")
            if connection.execute("SELECT id FROM equipment WHERE id = ?", (equipment_id,)).fetchone() is None:
                raise HTTPException(status_code=404, detail="Equipment was not found.")
            if connection.execute("SELECT id FROM equipment_loans WHERE equipment_id = ? AND returned_at IS NULL", (equipment_id,)).fetchone():
                raise HTTPException(status_code=409, detail="Someone has already checked this equipment out. Refresh to see who has it.")
            timestamp = datetime.now(timezone.utc).isoformat(timespec="seconds")
            cursor = connection.execute(
                "INSERT INTO equipment_loans(equipment_id, borrower, checked_out_at) VALUES (?, ?, ?)",
                (equipment_id, borrower, timestamp),
            )
            checkout_id = cursor.lastrowid
    return {"id": checkout_id, "equipment_id": equipment_id, "borrower": borrower,
            "checked_out_at": timestamp, "message": "Equipment checked out."}


@app.post("/equipment/{equipment_id}/checkin")
def checkin_equipment(equipment_id: int, item: EquipmentCheckin):
    with closing(sqlite3.connect(DATABASE)) as connection:
        with connection:
            connection.execute("BEGIN IMMEDIATE")
            if connection.execute("SELECT id FROM equipment WHERE id = ?", (equipment_id,)).fetchone() is None:
                raise HTTPException(status_code=404, detail="Equipment was not found.")
            timestamp = datetime.now(timezone.utc).isoformat(timespec="seconds")
            cursor = connection.execute(
                "UPDATE equipment_loans SET returned_at = ? WHERE id = ? AND equipment_id = ? AND returned_at IS NULL",
                (timestamp, item.checkout_id, equipment_id),
            )
            if cursor.rowcount != 1:
                raise HTTPException(status_code=409, detail="This checkout has changed. Refresh before returning equipment.")
    return {"id": item.checkout_id, "equipment_id": equipment_id,
            "returned_at": timestamp, "message": "Equipment checked in."}


from finance import router as finance_router
app.include_router(finance_router)

from research import router as research_router
app.include_router(research_router)

from jobs import router as jobs_router
app.include_router(jobs_router)
