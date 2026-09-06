import Foundation

enum DiskStats {
    static func volumes() -> [VolumeSample] {
        let keys: [URLResourceKey] = [
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
            .volumeIsRootFileSystemKey,
            .volumeIsBrowsableKey
        ]
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) ?? []

        var samples: [VolumeSample] = []
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            if values.volumeIsBrowsable == false { continue }
            let total = UInt64(values.volumeTotalCapacity ?? 0)
            guard total > 0 else { continue }
            let available = UInt64(
                values.volumeAvailableCapacityForImportantUsage
                    ?? Int64(values.volumeAvailableCapacity ?? 0)
            )
            let used = total > available ? total - available : 0
            let name = values.volumeName?.trimmingCharacters(in: .whitespacesAndNewlines)
            samples.append(
                VolumeSample(
                    name: (name?.isEmpty == false ? name : url.lastPathComponent) ?? "Disk",
                    path: url.path,
                    used: used,
                    total: total,
                    isBoot: values.volumeIsRootFileSystem == true || url.path == "/"
                )
            )
        }

        if !samples.contains(where: \.isBoot), let boot = bootVolume() {
            samples.insert(boot, at: 0)
        }
        return samples
    }

    static func bootVolume() -> VolumeSample? {
        volumes().first(where: \.isBoot) ?? statfsVolume(path: "/", name: "Macintosh HD", isBoot: true)
    }

    private static func statfsVolume(path: String, name: String, isBoot: Bool) -> VolumeSample? {
        var fs = statfs()
        guard statfs(path, &fs) == 0 else { return nil }
        let block = UInt64(fs.f_bsize)
        let total = UInt64(fs.f_blocks) * block
        let free = UInt64(fs.f_bavail) * block
        guard total > 0 else { return nil }
        return VolumeSample(
            name: name,
            path: path,
            used: total > free ? total - free : 0,
            total: total,
            isBoot: isBoot
        )
    }
}
