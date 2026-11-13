FROM python:3.12-alpine

# Install system dependencies for psycopg2-binary and health checks
RUN apk add --no-cache ca-certificates libpq

# Create app user
RUN addgroup -S app && adduser app -S -G app

# Set working directory
WORKDIR /home/app/

# Copy requirements and install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Create function directory
RUN mkdir -p function && chown -R app:app /home/app

# Copy index.py (Flask wrapper)
COPY index.py .

# Copy user's function code
COPY function/ ./function/

# Switch to non-root user
USER app

# Expose port
EXPOSE 8080

# Run Flask app
CMD ["python", "index.py"]
