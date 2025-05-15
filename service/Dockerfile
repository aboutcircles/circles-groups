FROM python:3.10-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY src /app/src
# Expose the port for the health server
EXPOSE 8080
CMD ["python", "-m", "src.main"]
