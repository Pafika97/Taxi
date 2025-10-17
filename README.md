# Taxi Bid Backend (FastAPI)

## Запуск (Windows)
```bash
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

Проверка: откройте http://127.0.0.1:8000/health -> {"ok": true}

## Доступ из интернета
Самый простой способ — ngrok:
```bash
ngrok http 8000
```
Возьмите выданный https-URL и подставьте его в мобильное приложение (константа `backendBase`).
