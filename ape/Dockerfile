FROM ghcr.io/apeworx/ape:v0.8.50

USER root

COPY requirements.txt .

RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt && rm -f requirements.txt

USER 1000
WORKDIR /home/harambe/project
