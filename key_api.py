import datetime
import logging
import os
import re
import secrets
import sqlite3
import string
import threading
from contextlib import closing
from pathlib import Path

import telebot
from flask import Flask, jsonify, request, send_file
from waitress import serve

app = Flask(__name__)
logger = logging.getLogger(__name__)
KEY_PATTERN = re.compile(r"^DRT EXTERNAL [A-Z0-9]{5}$")
DEFAULT_DATABASE_PATH = Path(__file__).resolve().with_name("keys.db")

def database_path():
    configured_path = os.environ.get("KEYS_DB_PATH")
    path = (
        Path(configured_path).expanduser()
        if configured_path
        else DEFAULT_DATABASE_PATH
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    return path


def connect_database():
    connection = sqlite3.connect(database_path(), timeout=10)
    connection.row_factory = sqlite3.Row
    return connection


def init_db():
    with closing(connect_database()) as connection:
        with connection:
            connection.execute(
                """
                CREATE TABLE IF NOT EXISTS keys (
                    key TEXT PRIMARY KEY,
                    used INTEGER NOT NULL DEFAULT 0 CHECK (used IN (0, 1)),
                    device_id TEXT,
                    duration_days INTEGER NOT NULL DEFAULT 7,
                    expires_at TEXT
                )
                """
            )
            columns = {
                row["name"]
                for row in connection.execute("PRAGMA table_info(keys)")
            }
            if "duration_days" not in columns:
                connection.execute(
                    "ALTER TABLE keys "
                    "ADD COLUMN duration_days INTEGER NOT NULL DEFAULT 7"
                )
            if "expires_at" not in columns:
                connection.execute(
                    "ALTER TABLE keys ADD COLUMN expires_at TEXT"
                )


def generate_key_string():
    suffix = "".join(
        secrets.choice(string.ascii_uppercase + string.digits) for _ in range(5)
    )
    return f"DRT EXTERNAL {suffix}"


def store_generated_key(duration_days=7):
    for _ in range(10):
        license_key = generate_key_string()
        with closing(connect_database()) as connection:
            try:
                with connection:
                    connection.execute(
                        "INSERT INTO keys (key, used, duration_days) VALUES (?, 0, ?)",
                        (license_key, duration_days),
                    )
                return license_key
            except sqlite3.IntegrityError:
                continue
    raise RuntimeError(
        "No se pudo generar una key única después de varios intentos."
    )


def send_welcome(bot, message):
    bot.reply_to(
        message,
        "¡Bienvenido al sistema de licencias!\n\n"
        "Comandos disponibles:\n"
        "/genkey 7 - Genera licencia de 7 días\n"
        "/genkey 15 - Genera licencia de 15 días\n"
        "/genkey 31 - Genera licencia de 31 días",
    )


def generate_license_for_admin(bot, message, admin_id):
    if message.from_user is None or message.from_user.id != admin_id:
        bot.reply_to(message, "No tienes permisos para generar licencias.")
        return

    # Extraer los días del comando (ej: /genkey 15 -> 15)
    args = message.text.split()
    duration_days = 7  # Por defecto 7 días
    if len(args) > 1:
        try:
            parsed_days = int(args[1])
            if parsed_days in [7, 15, 31]:
                duration_days = parsed_days
            else:
                bot.reply_to(
                    message, "Duración no válida. Usa 7, 15 o 31 días."
                )
                return
        except ValueError:
            bot.reply_to(
                message, "Formato incorrecto. Ejemplo: /genkey 15"
            )
            return

    try:
        license_key = store_generated_key(duration_days)
    except (OSError, sqlite3.Error, RuntimeError):
        logger.exception(
            "No se pudo generar una licencia solicitada por Telegram."
        )
        bot.reply_to(message, "No se pudo generar la licencia.")
        return

    bot.reply_to(
        message,
        f"Licencia generada ({duration_days} días):\n`{license_key}`\n\n"
        "Se activará en el primer dispositivo que la use.",
        parse_mode="Markdown",
    )


def create_bot(token, admin_id):
    bot = telebot.TeleBot(token)

    @bot.message_handler(commands=["start"])
    def handle_start(message):
        send_welcome(bot, message)

    @bot.message_handler(commands=["genkey"])
    def handle_generate_key(message):
        generate_license_for_admin(bot, message, admin_id)

    return bot


@app.route("/verify", methods=["POST"])
def verify_key():
    if not request.is_json:
        return jsonify({"status": "error", "message": "Se requiere JSON."}), 400

    data = request.get_json(silent=True)
    if not isinstance(data, dict):
        return (
            jsonify({"status": "error", "message": "El cuerpo JSON no es válido."}),
            400,
        )

    user_key = data.get("key")
    device_id = data.get("device_id")
    if not isinstance(user_key, str) or not KEY_PATTERN.fullmatch(user_key):
        return (
            jsonify(
                {
                    "status": "error",
                    "message": "La licencia no tiene un formato válido.",
                }
            ),
            400,
        )
    if not isinstance(device_id, str) or not device_id.strip() or len(device_id) > 255:
        return (
            jsonify(
                {
                    "status": "error",
                    "message": "El identificador del dispositivo no es válido.",
                }
            ),
            400,
        )

    now = datetime.datetime.utcnow()

    try:
        with closing(connect_database()) as connection:
            connection.execute("BEGIN IMMEDIATE")
            row = connection.execute(
                "SELECT used, device_id, duration_days, expires_at FROM keys WHERE key = ?",
                (user_key,),
            ).fetchone()

            if row is None:
                connection.rollback()
                return (
                    jsonify(
                        {
                            "status": "invalid",
                            "message": "La licencia no existe.",
                        }
                    ),
                    404,
                )

            # Verificar si ya expiró
            if row["expires_at"]:
                expires_at = datetime.datetime.fromisoformat(row["expires_at"])
                if now > expires_at:
                    connection.rollback()
                    return (
                        jsonify(
                            {
                                "status": "expired",
                                "message": "La licencia ha expirado.",
                            }
                        ),
                        403,
                    )

            if row["used"]:
                connection.rollback()
                if row["device_id"] == device_id:
                    return jsonify(
                        {
                            "status": "success",
                            "message": "Reautenticación exitosa.",
                        }
                    )
                return (
                    jsonify(
                        {
                            "status": "error",
                            "message": "La licencia ya fue activada en otro dispositivo.",
                        }
                    ),
                    403,
                )

            # Activar y calcular fecha de expiración
            expires_at = now + datetime.timedelta(days=row["duration_days"])
            connection.execute(
                "UPDATE keys SET used = 1, device_id = ?, expires_at = ? WHERE key = ? AND used = 0",
                (device_id, expires_at.isoformat(), user_key),
            )
            connection.commit()
    except (OSError, sqlite3.Error):
        logger.exception("Falló la verificación de una licencia.")
        return (
            jsonify(
                {"status": "error", "message": "No se pudo verificar la licencia."}
            ),
            500,
        )

    return jsonify({"status": "success", "message": "Licencia activada correctamente."})


@app.route("/preview", methods=["GET"])
def preview():
    preview_path = Path(__file__).resolve().with_name(".rx7-preview.html")
    return send_file(preview_path, mimetype="text/html")


@app.route("/assets/BrandLogo.png", methods=["GET"])
def preview_brand_logo():
    logo_path = (
        Path(__file__).resolve().parent
        / "ThreeOneOSFive"
        / "Assets.xcassets"
        / "BrandLogo.imageset"
        / "BrandLogo.png"
    )
    return send_file(logo_path, mimetype="image/png")


def main():
    init_db()
    port = int(os.environ.get("PORT", 5000))
    server_options = {
        "host": "0.0.0.0",
        "port": port,
    }

    if os.environ.get("ENABLE_TELEGRAM_BOT", "").lower() not in {
        "1",
        "true",
        "yes",
    }:
        serve(app, **server_options)
        return

    token = os.environ.get("TELEGRAM_BOT_TOKEN")
    admin_id_value = os.environ.get("TELEGRAM_ADMIN_ID")
    if not token or not admin_id_value:
        raise RuntimeError(
            "Configura TELEGRAM_BOT_TOKEN y TELEGRAM_ADMIN_ID antes de activar "
            "ENABLE_TELEGRAM_BOT."
        )
    try:
        admin_id = int(admin_id_value)
    except ValueError as error:
        raise RuntimeError("TELEGRAM_ADMIN_ID debe ser un número entero.") from error

    bot = create_bot(token, admin_id)

    server_thread = threading.Thread(
        target=serve,
        args=(app,),
        kwargs=server_options,
        daemon=True,
    )
    server_thread.start()
    bot.infinity_polling(skip_pending=True)


if __name__ == "__main__":
    main()