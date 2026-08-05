import UWP

import WinAppSDK

extension RuntimeInfo {
    static var sdkVersion: String {
        switch RuntimeInfo.version {
        case PackageVersion(major: 8000, minor: 616, build: 304, revision: 0):
            return "1.8.0"
        case PackageVersion(major: 8000, minor: 806, build: 2252, revision: 0):
            return "1.8.6"
        case PackageVersion(major: 8000, minor: 836, build: 2153, revision: 0):
            return "1.8.7"
        case PackageVersion(major: 8000, minor: 879, build: 2017, revision: 0):
            return "1.8.9"
        case PackageVersion(major: 8000, minor: 921, build: 1539, revision: 0):
            return "1.8.10"
        default:
            return RuntimeInfo.asString
        }
    }
}
