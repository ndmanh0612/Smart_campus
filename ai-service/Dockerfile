FROM python:3.12-slim-bookworm
WORKDIR /app/ai-service
COPY requirements.lock.txt ./
RUN pip install --no-cache-dir -r requirements.lock.txt
COPY app.py runtime.py ./
USER 10001:10001
CMD ["python","-m","uvicorn","app:app","--host","0.0.0.0","--port","8082","--workers","1"]
