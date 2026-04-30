FROM python:3.13-slim

WORKDIR /app

# Make Python output unbuffered (better logs in Docker/CI) and avoid .pyc files
ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1

# Install dependencies first to leverage Docker layer caching
COPY requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt

# Copy application source code
COPY . /app

# Default bind address/port for container runtime (can be overridden via env)
ENV HOST=0.0.0.0
ENV PORT=5000

EXPOSE 5000

# Entry point: start the application
CMD ["python", "app.py"]
