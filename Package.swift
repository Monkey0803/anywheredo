// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AnywhereDo",
    // 有本地化资源时必须声明开发语言：系统语言没匹配到时回退到它。
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "AnywhereDo", targets: ["AnywhereDo"]),
        .library(name: "AnywhereDoCore", targets: ["AnywhereDoCore"]),
    ],
    targets: [
        // 纯 Foundation 的分析内核：可单测，不依赖 AppKit。
        .target(
            name: "AnywhereDoCore",
            path: "Sources/AnywhereDoCore",
            resources: [.process("Resources")]
        ),
        // AppKit 界面外壳：菜单栏图标 + 鼠标旁弹窗。
        .executableTarget(
            name: "AnywhereDo",
            dependencies: ["AnywhereDoCore"],
            path: "Sources/AnywhereDo"
        ),
        .testTarget(
            name: "AnywhereDoCoreTests",
            dependencies: ["AnywhereDoCore"],
            path: "Tests/AnywhereDoCoreTests"
        ),
    ]
)
