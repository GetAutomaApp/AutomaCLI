import Foundation

internal struct GrafanaStateFile: Codable {
    internal var dashboards: [String: GrafanaDashboardState]
    internal var alertRules: [String: GrafanaAlertRuleState]

    internal init(
        dashboards: [String: GrafanaDashboardState] = [:],
        alertRules: [String: GrafanaAlertRuleState] = [:]
    ) {
        self.dashboards = dashboards
        self.alertRules = alertRules
    }
}

internal struct GrafanaDashboardState: Codable, HasUID {
    internal var uid: String
    internal var id: Int?
    internal var title: String?
}

internal struct GrafanaAlertRuleState: Codable, HasUID {
    internal var uid: String
    internal var title: String?
}

internal struct GrafanaRenderManifest: Codable {
    internal var environment: String
    internal var renderedAt: String
    internal var outputs: [GrafanaRenderedArtifact]
}

internal struct GrafanaRenderedArtifact: Codable {
    internal var key: String
    internal var source: String
    internal var output: String
    internal var kind: String
}

internal enum GrafanaTemplateSupport {
    internal static let rootDir = "grafana"
    internal static let templatesDir = "grafana/templates"
    internal static let renderedDir = "grafana/rendered"
    internal static let stateDir = "grafana/state"
    internal static let manifestFileName = "manifest.json"

    internal static func stateEnvironmentDir(environment: String) -> String {
        "\(stateDir)/\(environment)"
    }

    internal static func dashboardStateDir(environment: String) -> String {
        "\(stateEnvironmentDir(environment: environment))/dashboards"
    }

    internal static func alertStateDir(environment: String) -> String {
        "\(stateEnvironmentDir(environment: environment))/alerts"
    }

    internal static func legacyStatePath(environment: String) -> String {
        "\(stateDir)/\(environment).json"
    }

    internal static func renderedEnvironmentDir(environment: String) -> String {
        "\(renderedDir)/\(environment)"
    }

    internal static func manifestPath(environment: String) -> String {
        "\(renderedEnvironmentDir(environment: environment))/\(manifestFileName)"
    }

    internal static func ensureDirectory(_ path: String) throws {
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: path),
            withIntermediateDirectories: true
        )
    }

    internal static func writeJSON<T: Encodable>(_ value: T, to path: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    internal static func readState(environment: String) throws -> GrafanaStateFile {
        var state = GrafanaStateFile()
        let envDir = stateEnvironmentDir(environment: environment)

        if !FileManager.default.fileExists(atPath: envDir) {
            let legacyPath = legacyStatePath(environment: environment)
            if FileManager.default.fileExists(atPath: legacyPath) {
                let legacyData = try Data(contentsOf: URL(fileURLWithPath: legacyPath))
                return try JSONDecoder().decode(GrafanaStateFile.self, from: legacyData)
            }
            return state
        }

        state.dashboards = try readRecords(
            in: dashboardStateDir(environment: environment),
            as: GrafanaDashboardState.self
        )
        state.alertRules = try readRecords(
            in: alertStateDir(environment: environment),
            as: GrafanaAlertRuleState.self
        )

        return state
    }

    internal static func writeState(_ state: GrafanaStateFile, environment: String) throws {
        let envDir = stateEnvironmentDir(environment: environment)
        try ensureDirectory(envDir)
        var normalized = state
        normalizeStateForWrite(state: &normalized)
        try writeRecords(normalized.dashboards, to: dashboardStateDir(environment: environment))
        try writeRecords(normalized.alertRules, to: alertStateDir(environment: environment))
    }

    private static func readRecords<T: Decodable>(in directory: String, as _: T.Type) throws -> [String: T] {
        guard FileManager.default.fileExists(atPath: directory) else {
            return [:]
        }

        guard let enumerator = FileManager.default.enumerator(atPath: directory) else {
            return [:]
        }

        var output: [String: T] = [:]
        for case let file as String in enumerator where file.hasSuffix(".json") {
            let key = (file as NSString).deletingPathExtension
            let filePath = "\(directory)/\(file)"
            let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
            output[key] = try JSONDecoder().decode(T.self, from: data)
        }
        return output
    }

    private static func writeRecords<T: Encodable>(_ records: [String: T], to directory: String) throws {
        try ensureDirectory(directory)

        let existingFiles = try FileManager.default.contentsOfDirectory(atPath: directory)
            .filter { $0.hasSuffix(".json") }
        let targetFiles = Set(records.keys.map { "\($0).json" })
        for file in existingFiles where !targetFiles.contains(file) {
            try FileManager.default.removeItem(atPath: "\(directory)/\(file)")
        }

        for (key, value) in records {
            try writeJSON(value, to: "\(directory)/\(key).json")
        }
    }

    private static func normalizeStateForWrite(state: inout GrafanaStateFile) {
        state.dashboards = dedupeByUID(records: state.dashboards)
        state.alertRules = dedupeByUID(records: state.alertRules)
    }

    private static func dedupeByUID<T>(records: [String: T]) -> [String: T] where T: HasUID {
        var grouped: [String: [String]] = [:]
        for (key, value) in records {
            grouped[value.uid, default: []].append(key)
        }

        var output = records
        for (_, keys) in grouped where keys.count > 1 {
            let keeper = preferredStateKey(keys: keys)
            for key in keys where key != keeper {
                output.removeValue(forKey: key)
            }
        }
        return output
    }

    private static func preferredStateKey(keys: [String]) -> String {
        keys.sorted { lhs, rhs in
            let lhsLooksTemplateKey = lhs.contains(".")
            let rhsLooksTemplateKey = rhs.contains(".")
            if lhsLooksTemplateKey != rhsLooksTemplateKey {
                return lhsLooksTemplateKey
            }
            return lhs < rhs
        }.first ?? keys[0]
    }

    internal static func detectKind(from data: Data) -> String? {
        guard
            let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        if value["dashboard"] is [String: Any] {
            return "dashboard"
        }

        if value["condition"] != nil || value["data"] != nil || value["folderUID"] != nil || value["folderUid"] != nil {
            return "alert"
        }

        return nil
    }

    internal static func credentialsFilePath(environment: String) -> String {
        "Secrets/Grafana/\(environment)/creds.md"
    }

    internal static func loadGrafanaCredentials(environment: String) throws -> GrafanaConfig {
        let credsPath = credentialsFilePath(environment: environment)
        guard FileManager.default.fileExists(atPath: credsPath) else {
            throw CLIError.shellError(
                message: "Missing Grafana credentials file at \(credsPath).",
                error: "Expected .env-style entries for GRAFANA_URL and GRAFANA_AUTH_TOKEN."
            )
        }

        let content = try String(contentsOfFile: credsPath, encoding: .utf8)
        let env = parseDotEnv(content)
        guard
            let url = env["GRAFANA_URL"],
            let token = env["GRAFANA_AUTH_TOKEN"],
            !url.isEmpty,
            !token.isEmpty
        else {
            throw CLIError.shellError(
                message: "Invalid Grafana credentials format in \(credsPath).",
                error: "Expected GRAFANA_URL and GRAFANA_AUTH_TOKEN variables."
            )
        }

        return GrafanaConfig(url: url, token: token)
    }

    private static func parseDotEnv(_ content: String) -> [String: String] {
        var values: [String: String] = [:]
        let lines = content.split(whereSeparator: \.isNewline)

        for rawLine in lines {
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") {
                continue
            }

            guard let equalsIndex = line.firstIndex(of: "=") else {
                continue
            }

            let key = String(line[..<equalsIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            var value = String(line[line.index(after: equalsIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)

            if value.count >= 2,
               (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
               (value.hasPrefix("'") && value.hasSuffix("'")) {
                value.removeFirst()
                value.removeLast()
            }

            values[key] = value
        }

        return values
    }
}

internal protocol HasUID {
    var uid: String { get }
}
