import html
import os

from flask import Flask, jsonify, request

app = Flask(__name__)


def make_greeting(name: str) -> str:
    return f"Xin chào, {name.strip() or 'bạn'}!"


def current_environment() -> str:
    return os.getenv("APP_ENV", "local")


@app.get("/")
def home():
    environment = html.escape(current_environment())
    return f"""<!doctype html>
<html lang="vi">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>CI/CD Python Demo</title>
</head>
<body style="font-family: Arial; max-width: 700px;
             margin: 80px auto; line-height: 1.6; padding: 0 16px;">
    <h1>Ứng dụng CI/CD Python + Docker</h1>
    <p>Ứng dụng Flask đã chạy thành công trong container Docker.</p>
    <p><strong>Môi trường:</strong> {environment}</p>
    <p>Kiểm tra hệ thống: <a href="/health">/health</a></p>
    <p>API thử nghiệm: <a href="/api/greeting?name=Sinh%20vien">
        /api/greeting</a></p>
</body>
</html>"""


@app.get("/health")
def health():
    return (
        jsonify(
            status="ok",
            service="cicd-python-demo",
            environment=current_environment(),
        ),
        200,
    )


@app.get("/api/greeting")
def greeting():
    name = request.args.get("name", "")
    return jsonify(message=make_greeting(name))


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8000, debug=False)
