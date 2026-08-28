# syntax=docker/dockerfile:1

# ---------------------------------------------------------------------------
# Build stage — compiles the shelf server demo binary.
# Build from the MONOREPO ROOT so the local path dependencies
# (flutter_patcher_core, flutter_patcher_plugin_core) resolve:
#   docker build -f packages/server/Dockerfile -t flutter-patcher-server .
# ---------------------------------------------------------------------------
FROM dart:3.3-sdk AS build
WORKDIR /build
COPY . /build
WORKDIR /build/packages/server
RUN dart pub get
RUN dart compile exe bin/server.dart -o /build/out/server

# ---------------------------------------------------------------------------
# Runtime stage
# ---------------------------------------------------------------------------
FROM debian:stable-slim
WORKDIR /app
COPY --from=build /build/out/server /app/server
EXPOSE 8080
ENV PORT=8080
# Mount a real database/storage plugin by replacing bin/server.dart with a
# host app that wires `createHotUpdater` (see DEPLOY.md). The demo binary
# below uses an in-memory database + storage and is intended for smoke tests.
CMD ["/app/server"]
