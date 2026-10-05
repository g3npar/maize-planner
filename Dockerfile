# The planner API server for hosting outside your machine, e.g. on Render.
# The web UI is served by GitHub Pages and talks to this server, so it only
# runs the headless `planner` service (core/planner.jac), not the `web` app:
# serving `web` rebuilds the client bundle on boot and needs ~1 GB, well over
# Render's free 512 MB.
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

# Compile the server modules ahead of time (--faux compiles and prints the
# endpoints without serving). Compiling peaks near 500 MB, so doing it at boot
# gets the container killed; with the cache warm the server starts in ~60 MB.
# Drop the embedded database --faux creates so it doesn't ship in the image.
RUN jac run --faux planner && rm -rf .jac/data

EXPOSE 8000
ENTRYPOINT []
CMD ["jac", "run", "--serve", "planner", "--host", "0.0.0.0"]
