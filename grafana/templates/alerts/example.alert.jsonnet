local env = std.extVar("environment");

{
  uid: "example-alert-" + env,
  title: "Example Alert (" + env + ")",
  ruleGroup: "automa",
  folder: "General",
  condition: "A",
  noDataState: "NoData",
  execErrState: "Error",
  "for": "2m",
  intervalSeconds: 60,
  labels: { service: "example", environment: env },
  annotations: { summary: "Example alert from automa" },
  data: [
    {
      refId: "A",
      relativeTimeRange: { from: 600, to: 0 },
      datasourceUid: "__expr__",
      model: {
        refId: "A",
        type: "math",
        expression: "1",
        datasource: { type: "__expr__", uid: "__expr__" },
        intervalMs: 1000,
        maxDataPoints: 43200,
      },
    },
  ],
}