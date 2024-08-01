// swift-tools-version: 5.10

import PackageDescription

let package = Package(
	name: "swiftui-reluxrouter",
	platforms: [
		.iOS(.v16),
		.macOS(.v13),
		.watchOS(.v9),
		.tvOS(.v16),
		.macCatalyst(.v16),
	],
	products: [
		.library(
			name: "ReluxRouter",
			targets: ["ReluxRouter"]
		),
	],
	dependencies:      [
		.package(url: "https://github.com/ivalx1s/darwin-relux.git", from: "7.0.0"),
	],
	targets: [
		.target(
			name: "ReluxRouter",
			dependencies:  [
				.product(name: "Relux", package: "darwin-relux"),
			],
			path: "Sources"
		),
	]
)
