FROM python:3.11-slim

WORKDIR /app

# System-Abhängigkeiten installieren
RUN apt-get update && apt-get install -y \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Python-Abhängigkeiten kopieren und installieren
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Server-Code kopieren
COPY server.py .

# Port freigeben
EXPOSE 8000

# Nicht-root User erstellen
RUN useradd -m -u 1000 mcpuser && chown -R mcpuser:mcpuser /app
USER mcpuser

# HTTP Server starten
CMD ["python", "server.py"]

