import CoreGraphics
import Darwin
import Foundation

@main
struct ScrollHelperMain {
    static func main() {
        let store = ToolStateStore.shared
        guard store.current.scrollReverseEnabled else {
            store.update { $0.scrollHelperPID = 0 }
            return
        }
        store.update { $0.scrollHelperPID = Int(getpid()) }

        let devices = DeviceMonitor()
        devices.onChange = { snapshot in
            applyPolicy(mice: snapshot.mice)
        }
        applyPolicy(mice: DeviceMonitor.listMiceOnce())
        devices.start()

        guard ScrollReverseService.shared.start() else {
            fputs("yeobun-scroll: Accessibility permission is required.\n", stderr)
            store.update { $0.scrollHelperPID = 0 }
            exit(3)
        }

        DistributedNotificationCenter.default().addObserver(
            forName: YeobunPaths.scrollReloadNotification,
            object: nil,
            queue: .main
        ) { _ in
            ToolStateStore.shared.reload()
            let state = ToolStateStore.shared.current
            if !state.scrollReverseEnabled {
                shutdown(devices: devices)
                CFRunLoopStop(CFRunLoopGetMain())
                return
            }
            applyPolicy(mice: DeviceMonitor.listMiceOnce())
            ScrollReverseService.shared.reEnableIfNeeded()
        }

        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler {
            shutdown(devices: devices)
            CFRunLoopStop(CFRunLoopGetMain())
        }
        source.resume()

        CFRunLoopRun()
    }

    private static func applyPolicy(mice: [MouseDevice]) {
        let state = ToolStateStore.shared.current
        DeviceMonitor.reverseEnabledIDs = ScrollPolicy.enabledIDs(
            mice: mice,
            map: state.scrollReverseByDevice,
            enabled: state.scrollReverseEnabled
        )
    }

    private static func shutdown(devices: DeviceMonitor) {
        ScrollReverseService.shared.stop()
        devices.stop()
        ToolStateStore.shared.update { $0.scrollHelperPID = 0 }
    }
}
