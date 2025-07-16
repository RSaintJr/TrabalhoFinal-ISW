FROM python:3.11-slim

WORKDIR /app
COPY . .

RUN pip install requests redis

CMD ["python", "app.py"]
