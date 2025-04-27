FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

WORKDIR /code

COPY . .

RUN pip install --no-cache-dir -r requirements.txt

ENV STORAGE_TYPE=file

EXPOSE 5000

CMD ["python", "run.py"]
