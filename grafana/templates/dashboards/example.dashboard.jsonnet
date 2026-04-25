local env = std.extVar("environment");

{
  overwrite: true,
  message: "Managed by automa",
  folder: "General",
  dashboard: {
    uid: "example-dashboard-" + env,
    title: "Example Dashboard (" + env + ")",
    tags: ["automa", env],
    schemaVersion: 39,
    version: 1,
    refresh: "30s",
    timezone: "browser",
    editable: true,
    panels: [],
  },
}