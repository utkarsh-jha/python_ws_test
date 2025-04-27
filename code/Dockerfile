FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

COPY requirements.txt .

RUN pip install --no-cache-dir -r requirements.txt

WORKDIR /

COPY . .

ENV STORAGE_TYPE=file

EXPOSE 5000

WORKDIR /

CMD ["python", "run.py"]
