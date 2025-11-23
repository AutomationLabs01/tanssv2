.PHONY: help install test docker-build docker-up docker-down docker-logs clean

help:
	@echo "Tanss MCP Server v2 - Verfügbare Befehle:"
	@echo "  make install      - Installiert Python-Abhängigkeiten"
	@echo "  make test         - Führt Tests aus"
	@echo "  make docker-build - Baut Docker Image"
	@echo "  make docker-up    - Startet Docker Container"
	@echo "  make docker-down  - Stoppt Docker Container"
	@echo "  make docker-logs  - Zeigt Docker Logs"
	@echo "  make clean        - Bereinigt temporäre Dateien"

install:
	pip install -r requirements.txt

test:
	python client_test.py

docker-build:
	docker-compose build

docker-up:
	docker-compose up -d

docker-down:
	docker-compose down

docker-logs:
	docker-compose logs -f

clean:
	find . -type d -name __pycache__ -exec rm -r {} + 2>/dev/null || true
	find . -type f -name "*.pyc" -delete
	find . -type f -name "*.pyo" -delete

