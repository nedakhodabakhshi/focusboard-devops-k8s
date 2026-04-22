import os
import json
from functools import wraps
from datetime import datetime

from flask import Flask, render_template, request, redirect, url_for, session, flash
from werkzeug.security import generate_password_hash, check_password_hash
from dotenv import load_dotenv
import psycopg2
import psycopg2.extras
import redis

load_dotenv()

app = Flask(__name__)
app.secret_key = os.getenv("SECRET_KEY", "dev-secret-key")

redis_client = redis.Redis(
    host=os.getenv("REDIS_HOST", "cache"),
    port=int(os.getenv("REDIS_PORT", 6379)),
    decode_responses=True
)


def get_db_connection():
    conn = psycopg2.connect(
        dbname=os.getenv("DB_NAME"),
        user=os.getenv("DB_USER"),
        password=os.getenv("DB_PASSWORD"),
        host=os.getenv("DB_HOST"),
        port=os.getenv("DB_PORT")
    )
    return conn


def login_required(func):
    @wraps(func)
    def wrapper(*args, **kwargs):
        if "user_id" not in session:
            return redirect(url_for("login"))
        return func(*args, **kwargs)
    return wrapper


def build_tasks_cache_key(user_id, search, status, category, priority):
    return f"tasks:user:{user_id}:search:{search}:status:{status}:category:{category}:priority:{priority}"


def clear_user_tasks_cache(user_id):
    pattern = f"tasks:user:{user_id}:*"
    keys = redis_client.keys(pattern)
    if keys:
        redis_client.delete(*keys)


@app.route("/")
@login_required
def index():
    search = request.args.get("search", "").strip()
    status = request.args.get("status", "").strip()
    category = request.args.get("category", "").strip()
    priority = request.args.get("priority", "").strip()

    cache_key = build_tasks_cache_key(
        session["user_id"], search, status, category, priority
    )

    cached_tasks = redis_client.get(cache_key)

    if cached_tasks:
        tasks = json.loads(cached_tasks)
    else:
        query = "SELECT * FROM tasks WHERE user_id = %s"
        params = [session["user_id"]]

        if search:
            query += " AND title ILIKE %s"
            params.append(f"%{search}%")

        if status:
            query += " AND status = %s"
            params.append(status)

        if category:
            query += " AND category ILIKE %s"
            params.append(f"%{category}%")

        if priority:
            query += " AND priority = %s"
            params.append(priority)

        query += " ORDER BY id DESC"

        conn = get_db_connection()
        cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
        cur.execute(query, params)
        tasks = cur.fetchall()
        cur.close()
        conn.close()

        redis_client.setex(cache_key, 60, json.dumps(tasks, default=str))

    return render_template(
        "index.html",
        tasks=tasks,
        username=session.get("username"),
        filters={
            "search": search,
            "status": status,
            "category": category,
            "priority": priority
        }
    )


@app.route("/register", methods=["GET", "POST"])
def register():
    if request.method == "POST":
        username = request.form.get("username", "").strip()
        password = request.form.get("password", "").strip()

        if not username or not password:
            flash("Username and password are required.", "error")
            return redirect(url_for("register"))

        hashed_password = generate_password_hash(password)

        conn = get_db_connection()
        cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

        cur.execute("SELECT * FROM users WHERE username = %s", (username,))
        existing_user = cur.fetchone()

        if existing_user:
            cur.close()
            conn.close()
            flash("Username already exists.", "error")
            return redirect(url_for("register"))

        cur.execute(
            "INSERT INTO users (username, password) VALUES (%s, %s)",
            (username, hashed_password)
        )
        conn.commit()
        cur.close()
        conn.close()

        flash("Registration successful. Please login.", "success")
        return redirect(url_for("login"))

    return render_template("register.html")


@app.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "GET":
        session.clear()
        return render_template("login.html")

    username = request.form.get("username", "").strip()
    password = request.form.get("password", "").strip()

    conn = get_db_connection()
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    cur.execute("SELECT * FROM users WHERE username = %s", (username,))
    user = cur.fetchone()
    cur.close()
    conn.close()

    if user and check_password_hash(user["password"], password):
        session["user_id"] = user["id"]
        session["username"] = user["username"]
        flash("Login successful.", "success")
        return redirect(url_for("index"))

    flash("Invalid username or password.", "error")
    return redirect(url_for("login"))


@app.route("/logout")
def logout():
    session.clear()
    flash("You have been logged out.", "success")
    return redirect(url_for("login"))


@app.route("/add", methods=["POST"])
@login_required
def add_task():
    title = request.form.get("title", "").strip()
    category = request.form.get("category", "").strip()
    other_category = request.form.get("other_category", "").strip()
    priority = request.form.get("priority", "Medium").strip()

    if category == "Other" and other_category:
        category = other_category

    if title:
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute(
            """
            INSERT INTO tasks (user_id, title, category, status, priority, created_at)
            VALUES (%s, %s, %s, %s, %s, %s)
            """,
            (
                session["user_id"],
                title,
                category or "General",
                "Pending",
                priority or "Medium",
                datetime.now()
            )
        )
        conn.commit()
        cur.close()
        conn.close()

        clear_user_tasks_cache(session["user_id"])

    return redirect(url_for("index"))


@app.route("/complete/<int:task_id>", methods=["POST"])
@login_required
def complete_task(task_id):
    conn = get_db_connection()
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

    cur.execute(
        "SELECT * FROM tasks WHERE id = %s AND user_id = %s",
        (task_id, session["user_id"])
    )
    task = cur.fetchone()

    if task:
        cur.execute(
            "UPDATE tasks SET status = %s WHERE id = %s",
            ("Completed", task_id)
        )
        conn.commit()
        clear_user_tasks_cache(session["user_id"])

    cur.close()
    conn.close()
    return redirect(url_for("index"))


@app.route("/delete/<int:task_id>", methods=["POST"])
@login_required
def delete_task(task_id):
    conn = get_db_connection()
    cur = conn.cursor()
    cur.execute(
        "DELETE FROM tasks WHERE id = %s AND user_id = %s",
        (task_id, session["user_id"])
    )
    conn.commit()
    cur.close()
    conn.close()

    clear_user_tasks_cache(session["user_id"])

    flash("Task deleted successfully.", "success")
    return redirect(url_for("index"))


@app.route("/edit/<int:task_id>", methods=["GET", "POST"])
@login_required
def edit_task(task_id):
    conn = get_db_connection()
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

    cur.execute(
        "SELECT * FROM tasks WHERE id = %s AND user_id = %s",
        (task_id, session["user_id"])
    )
    task = cur.fetchone()

    if not task:
        cur.close()
        conn.close()
        flash("Task not found.", "error")
        return redirect(url_for("index"))

    if request.method == "POST":
        title = request.form.get("title", "").strip()
        category = request.form.get("category", "").strip()
        priority = request.form.get("priority", "Medium").strip()
        status = request.form.get("status", "Pending").strip()

        cur.execute(
            """
            UPDATE tasks
            SET title = %s, category = %s, priority = %s, status = %s
            WHERE id = %s AND user_id = %s
            """,
            (
                title,
                category or "General",
                priority or "Medium",
                status or "Pending",
                task_id,
                session["user_id"]
            )
        )
        conn.commit()
        cur.close()
        conn.close()

        clear_user_tasks_cache(session["user_id"])

        flash("Task updated successfully.", "success")
        return redirect(url_for("index"))

    cur.close()
    conn.close()
    return render_template("edit_task.html", task=task)


@app.route("/health")
def health():
    return {"status": "ok", "app": "FocusBoard"}


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)