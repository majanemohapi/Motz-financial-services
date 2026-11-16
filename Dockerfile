FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
    && apt-get install -y --no-install-recommends swi-prolog-nox ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY main.pl ./main.pl
COPY data ./data
COPY public ./public

# Render supplies PORT at runtime. Locally, the application defaults to 8080.
EXPOSE 8080
CMD ["swipl", "-q", "-s", "main.pl"]
