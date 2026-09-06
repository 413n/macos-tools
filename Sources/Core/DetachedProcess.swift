import Darwin
import Foundation

struct DetachedProcessError: LocalizedError {
    let errorDescription: String?
}

enum DetachedProcess {
    static func spawn(executable: String, arguments: [String]) throws -> pid_t {
        var pid: pid_t = 0
        var attr: posix_spawnattr_t? = nil
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETPGROUP))

        var actions: posix_spawn_file_actions_t? = nil
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        "/dev/null".withCString { path in
            _ = posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, path, O_RDONLY, 0)
            _ = posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, path, O_WRONLY, 0)
            _ = posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, path, O_WRONLY, 0)
        }

        let cArgs = ([executable] + arguments).map { strdup($0) } + [nil]
        defer {
            for pointer in cArgs {
                free(pointer)
            }
        }

        let status = cArgs.withUnsafeBufferPointer { argv in
            executable.withCString { path in
                posix_spawn(&pid, path, &actions, &attr, argv.baseAddress, environ)
            }
        }
        guard status == 0 else {
            throw DetachedProcessError(errorDescription: "Could not start \(executable) (\(status)).")
        }
        return pid
    }

    static func isRunning(pid: pid_t, commandContains needle: String) -> Bool {
        guard pid > 1, kill(pid, 0) == 0 else { return false }
        guard let name = commandName(of: pid) else { return false }
        return name.contains(needle)
    }

    static func commandName(of pid: pid_t) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-p", "\(pid)", "-o", "comm="]
        let stdout = Pipe()
        task.standardOutput = stdout
        task.standardError = FileHandle.nullDevice
        task.standardInput = FileHandle.nullDevice
        do {
            try task.run()
        } catch {
            return nil
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { return nil }
        let name = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name?.isEmpty == false ? name : nil
    }
}
