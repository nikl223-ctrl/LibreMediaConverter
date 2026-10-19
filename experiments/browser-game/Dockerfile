# Serves a browser-rendered original demo. No GPU and no native Steam engine.
FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 HOST=0.0.0.0 PORT=8765 BROWSER_GAME_DATA_DIR=/data
WORKDIR /srv/truck-browser
COPY server.py low_bandwidth.py game.js index.html styles.css ./
COPY assets ./assets
RUN useradd --no-create-home --uid 10001 --user-group browsergame \
    && mkdir -p /data && chown 10001:10001 /data
USER 10001:10001
EXPOSE 8765
HEALTHCHECK --interval=30s --timeout=5s CMD python -c "import urllib.request;urllib.request.urlopen('http://127.0.0.1:8765/health',timeout=3)"
CMD ["python","server.py"]
