import Foundation

struct LatestRelease {
    let version: String
    let pageURL: URL
}

enum UpdateCheckError: LocalizedError {
    case noRelease
    case badResponse
    case network(String)

    var errorDescription: String? {
        switch self {
        case .noRelease:
            return "No GitHub release yet"
        case .badResponse:
            return "Could not read GitHub releases"
        case .network(let message):
            return message
        }
    }
}

enum UpdateCheckService {
    static let githubRepo = "n6-studio/yeobun"
    static let latestReleaseURL = URL(string: "https://api.github.com/repos/n6-studio/yeobun/releases/latest")!
    static let releasesPageURL = URL(string: "https://github.com/n6-studio/yeobun/releases")!

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }

    static func fetchLatest(completion: @escaping (Result<LatestRelease, Error>) -> Void) -> URLSessionDataTask {
        var request = URLRequest(url: latestReleaseURL, timeoutInterval: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Yeobun/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                let nsError = error as NSError
                if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                    return
                }
                completion(.failure(UpdateCheckError.network(error.localizedDescription)))
                return
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 404 {
                completion(.failure(UpdateCheckError.noRelease))
                return
            }
            if status == 403 {
                completion(.failure(UpdateCheckError.network("GitHub rate limit — try again later")))
                return
            }
            guard (200...299).contains(status), let data else {
                completion(.failure(UpdateCheckError.badResponse))
                return
            }
            do {
                let decoded = try JSONDecoder().decode(GitHubRelease.self, from: data)
                let version = Self.normalized(decoded.tagName)
                guard !version.isEmpty, let page = URL(string: decoded.htmlURL) else {
                    completion(.failure(UpdateCheckError.badResponse))
                    return
                }
                completion(.success(LatestRelease(version: version, pageURL: page)))
            } catch {
                completion(.failure(UpdateCheckError.badResponse))
            }
        }
        task.resume()
        return task
    }

    static func compare(latest: String, current: String) -> ComparisonResult {
        let left = components(latest)
        let right = components(current)
        let count = max(left.count, right.count)
        for index in 0..<count {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b {
                return a < b ? .orderedAscending : .orderedDescending
            }
        }
        return .orderedSame
    }

    static func normalized(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("v") {
            return String(trimmed.dropFirst())
        }
        return trimmed
    }

    private static func components(_ version: String) -> [Int] {
        normalized(version)
            .split(separator: ".")
            .prefix(3)
            .map { Int($0) ?? 0 }
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: String

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}
