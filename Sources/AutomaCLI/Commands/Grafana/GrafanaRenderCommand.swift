import ConsoleKit
import Foundation

internal struct GrafanaRenderCommand: Command {
    var help: String { "Renders Grafana Jsonnet templates into JSON artifacts." }

    struct Signature: CommandSignature {
        @Option(name: "environment", help: "Environment value passed to Jsonnet as extVar(environment).")
        var environment: String?
    }

    func run(using context: CommandContext, signature: Signature) throws {
        let automaConfig = try ConfigHelper.getAutomaConfig()
        let environment = signature.environment ?? automaConfig.grafana.currentEnvironment

        let templateRoot = GrafanaTemplateSupport.templatesDir
        guard FileManager.default.fileExists(atPath: templateRoot) else {
            context.console.error("No templates found at \(templateRoot). Run `automa grafana init` first.")
            return
        }

        let outputRoot = GrafanaTemplateSupport.renderedEnvironmentDir(environment: environment)
        try GrafanaTemplateSupport.ensureDirectory(outputRoot)

        let jsonnetFiles = try collectJsonnetFiles(in: templateRoot)
        var outputs: [GrafanaRenderedArtifact] = []

        for source in jsonnetFiles {
            let relative = source.replacingOccurrences(of: "\(templateRoot)/", with: "")
            let output = "\(outputRoot)/\(relative.replacingOccurrences(of: ".jsonnet", with: ".json"))"
            let outputDir = (output as NSString).deletingLastPathComponent
            try GrafanaTemplateSupport.ensureDirectory(outputDir)

            let command = "jsonnet --ext-str environment=\(environment.shellEscapedArgument) \(source.shellEscapedArgument)"
            let shellOutput = try Shell.run(command)
            if shellOutput.isError {
                let stderr = shellOutput.stderr ?? "unknown error"
                throw CLIError.shellError(message: "Jsonnet render failed for \(source)", error: stderr)
            }

            let rendered = shellOutput.stdout ?? ""
            try rendered.write(toFile: output, atomically: true, encoding: .utf8)

            let kind = GrafanaTemplateSupport.detectKind(from: Data(rendered.utf8)) ?? "unknown"
            let key = ((relative as NSString).deletingPathExtension as NSString).lastPathComponent
            outputs.append(GrafanaRenderedArtifact(key: key, source: source, output: output, kind: kind))
        }

        let manifest = GrafanaRenderManifest(
            environment: environment,
            renderedAt: ISO8601DateFormatter().string(from: Date()),
            outputs: outputs
        )
        try GrafanaTemplateSupport.writeJSON(manifest, to: GrafanaTemplateSupport.manifestPath(environment: environment))
        context.console.success("Rendered \(outputs.count) Grafana artifacts for \(environment).")
    }

    private func collectJsonnetFiles(in root: String) throws -> [String] {
        guard let enumerator = FileManager.default.enumerator(atPath: root) else {
            return []
        }

        var files: [String] = []
        for case let path as String in enumerator where path.hasSuffix(".jsonnet") {
            files.append("\(root)/\(path)")
        }
        return files.sorted()
    }
}
