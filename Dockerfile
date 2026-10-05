# The planner server (API + web UI) for hosting outside your machine, e.g. on
# Render. The GitHub Pages site talks to this server.
#
# Environment:
#   JAC_DB_URL              Postgres URL (required on hosts without a disk,
#                           otherwise the embedded database is lost on restart)
#   JAC_SERVE_AUTH_SECRET   fixed JWT secret so sign-ins survive restarts
#   ANTHROPIC_API_KEY / OPENAI_API_KEY / GEMINI_API_KEY   optional, turns on AI
#   The server listens on port 8000.
FROM jaseci/jaclang:0.37.21

WORKDIR /app

# The image ships its bundled bun without the execute bit, and as root, so the
# non-root `jac` user can't run (or fix) it.
USER root
RUN chmod a+rx /opt/jac/state/rt/*/site/jaclang/client/_bun/bun
USER jac

COPY --chown=jac:jac . .

# Install npm packages and compile ahead of time so the server boots quickly.
RUN jac build --as client web

EXPOSE 8000
ENTRYPOINT []
CMD ["jac", "run", "--serve", "web", "--host", "0.0.0.0"]
