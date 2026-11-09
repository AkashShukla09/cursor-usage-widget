import CursorUsageLib
import Foundation

@main
enum WidgetMain {
    static func main() {
        if CommandLine.arguments.contains("--status") {
            runStatus()
            return
        }
        CursorUsageApp.main()
    }

    private static func runStatus() {
        WidgetSettings.registerDefaults()
        let source: UsageSource
        do {
            source = try statusSource()
        } catch {
            fputs(error.localizedDescription + "\n", stderr)
            exit(EXIT_FAILURE)
        }
        Task.detached {
            do {
                switch source {
                case .cursor:
                    let snapshot = try await CursorAPI.fetchSnapshot()
                    print(snapshot.statusText())
                case .claudeCode:
                    let snapshot = try await ClaudeAPI.fetchSnapshot()
                    print(snapshot.statusText())
                }
                exit(EXIT_SUCCESS)
            } catch {
                fputs(error.localizedDescription + "\n", stderr)
                exit(EXIT_FAILURE)
            }
        }
        dispatchMain()
    }

    private static func statusSource() throws -> UsageSource {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--source") else {
            return WidgetSettings.source()
        }
        guard index + 1 < arguments.count else {
            throw StatusError.unknownSource
        }
        switch arguments[index + 1].lowercased() {
        case "cursor":
            return .cursor
        case "claude", "claudecode", "claude-code":
            return .claudeCode
        default:
            throw StatusError.unknownSource
        }
    }
}

private enum StatusError: Error, LocalizedError {
    case unknownSource

    var errorDescription: String? {
        "Unknown source. Use --source cursor or --source claude."
    }
}
