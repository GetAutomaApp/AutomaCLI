import ConsoleKit
import Foundation

internal struct GrafanaInitCommand: Command {
    var help: String { "Creates Jsonnet scaffolding for Grafana templates." }

    struct Signature: CommandSignature {
        @Option(name: "environment", help: "Environment name for the initial local state file.")
        var environment: String?
    }

    func run(using context: CommandContext, signature: Signature) throws {
        let automaConfig = try ConfigHelper.getAutomaConfig()
        let environment = signature.environment ?? automaConfig.grafana.currentEnvironment

        try GrafanaTemplateSupport.ensureDirectory(GrafanaTemplateSupport.rootDir)
        try GrafanaTemplateSupport.ensureDirectory(GrafanaTemplateSupport.templatesDir)
        try GrafanaTemplateSupport.ensureDirectory("\(GrafanaTemplateSupport.templatesDir)/dashboards")
        try GrafanaTemplateSupport.ensureDirectory("\(GrafanaTemplateSupport.templatesDir)/alerts")
        try GrafanaTemplateSupport.ensureDirectory(GrafanaTemplateSupport.renderedDir)
        try GrafanaTemplateSupport.ensureDirectory(GrafanaTemplateSupport.stateDir)

        let dashboardTemplatePath = "\(GrafanaTemplateSupport.templatesDir)/dashboards/example.dashboard.jsonnet"
        let alertTemplatePath = "\(GrafanaTemplateSupport.templatesDir)/alerts/example.alert.jsonnet"
        let statePath = GrafanaTemplateSupport.stateEnvironmentDir(environment: environment)

        try writeIfMissing(
            path: dashboardTemplatePath,
            contents: """
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
            """
        )

        try writeIfMissing(
            path: alertTemplatePath,
            contents: """
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
            """
        )

        try GrafanaTemplateSupport.writeState(
            try GrafanaTemplateSupport.readState(environment: environment),
            environment: environment
        )

        context.console.success("Grafana Jsonnet scaffold ready.")
        context.console.print("Templates: \(GrafanaTemplateSupport.templatesDir)")
        context.console.print("State directory: \(statePath)")
    }

    private func writeIfMissing(path: String, contents: String) throws {
        if FileManager.default.fileExists(atPath: path) {
            return
        }
        try contents.write(toFile: path, atomically: true, encoding: .utf8)
    }
}
