#!/bin/sh

set -e

echo "Waiting for PostgreSQL..."

sleep 5

echo "Initializing database..."
python init_db.py || echo "DB already initialized"

echo "Starting application..."
exec gunicorn --bind 0.0.0.0:5000 app:app