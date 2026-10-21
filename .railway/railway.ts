// Railway IaC authoring file (`.railway/railway.ts`).
//
// This is the modern replacement for Config as Code: one file describing the
// whole project (service, volume, variables) managed with
//   railway config plan
//   railway config apply
// It needs the Railway CLI and `npm install railway`.
//
// It is a convenience mirror of the dashboard template, not a dependency of it.
// Deploying this repository from the dashboard only needs `railway.json`,
// `Dockerfile`, `.env.railway` and `docker-entrypoint.sh`. Delete this file if
// you manage the project from the dashboard only, so the two never fight over
// the same resources.
//
// The volume mount path must be exactly /app/data: the SQLite database, install
// id, config directory and telemetry payloads all live there, and the image
// already points every related variable at it.
import {
  defineRailway,
  github,
  preserve,
  project,
  service,
  volume,
} from "railway/iac";

// Upstream release this template was verified against. Upstream publishes tags
// (not long-lived release branches), and its `git clone --branch v2.4.6` works,
// so a tag is a valid pin for the `branch` field.
const SOURCE_REF = "v2.4.6";

export default defineRailway(() => {
  const data = volume("cartethyia-data", { sizeMB: 1024 });

  const cartethyia = service("Cartethyia", {
    source: github("risunCodex/Cartethyia", { branch: SOURCE_REF }),
    healthcheck: "/health/ready",
    healthcheckTimeout: 300,
    volumeMounts: {
      "/app/data": data,
    },
    env: {
      PORT: "12800",
      NODE_ENV: "production",
      LOG_LEVEL: "info",

      // Lite = embedded SQLite on the volume. Full mode needs PostgreSQL plus a
      // backup export/import; see DEPLOY.md.
      CARTETHYIA_DB_MODE: "lite",

      // Keep this stable: rotating it makes every stored provider credential
      // and API key unreadable. `preserve()` keeps whatever value Railway holds
      // instead of writing the secret into this file. Set it once with
      // `openssl rand -hex 32`.
      CARTETHYIA_ENCRYPTION_KEY: preserve(),

      // Resolved by Railway at deploy time from the service's public domain.
      // Generate the domain before the first apply.
      CARTETHYIA_PUBLIC_ORIGIN: "https://${{RAILWAY_PUBLIC_DOMAIN}}",

      // Railway's edge terminates TLS and cannot be allowlisted, so the gateway
      // reads the client address from the edge's forwarded headers.
      TRUSTED_PROXY_CIDRS: "platform",
    },
  });

  return project("Cartethyia", {
    resources: [cartethyia, data],
  });
});
