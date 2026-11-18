import os

from flask import Flask, jsonify, render_template, request

app = Flask(__name__)


def make_greeting(name: str) -> str:
    return f"Xin chào, {name.strip() or 'bạn'}!"


def current_environment() -> str:
    return os.getenv("APP_ENV", "local")


@app.get("/")
def home():
    return render_template(
        "index.html",
        environment=current_environment(),
    )


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
