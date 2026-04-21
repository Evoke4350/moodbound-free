import ProjectDescription

let project = Project(
    name: "moodbound",
    organizationName: "Moodbound",
    targets: [
        .target(
            name: "moodbound",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.Moodbound",
            deploymentTargets: .iOS("17.0"),
            infoPlist: .extendingDefault(with: [
                "CFBundleShortVersionString": .string("1.2.1"),
                "CFBundleVersion": .string("17"),
                "CFBundleIconName": .string("AppIcon"),
                "UILaunchScreen": .dictionary([:]),
                "UISupportedInterfaceOrientations": .array([
                    .string("UIInterfaceOrientationPortrait"),
                ]),
                "NSLocationWhenInUseUsageDescription": .string("Moodbound uses your location to load current weather conditions for your check-ins."),
                "NSHealthShareUsageDescription": .string("Moodbound reads sleep, heart rate, HRV, steps, and mindful minutes from Apple Health to enrich your check-ins and improve mood pattern detection."),
                "NSHealthUpdateUsageDescription": .string("Moodbound writes your mood as a State of Mind entry and records check-ins as mindful sessions in Apple Health."),
                // Export compliance: moodbound uses only EXEMPT encryption.
                // We rely entirely on Apple-platform primitives (HTTPS via
                // URLSession, SwiftData at-rest encryption, standard keychain)
                // plus HTTPS calls to AWS Bedrock. No custom cryptography,
                // no proprietary protocols, no on-device crypto beyond what
                // iOS provides. Under US export regulations 15 CFR 740.17
                // and Apple's documentation this is exempt — no ERN needed.
                //
                // Answering false here self-declares exemption at archive
                // time so TestFlight never asks (and never blocks on a
                // mismatched ERN lookup, which happened for build 7/8 when
                // the Info.plist was silent on this key). If moodbound ever
                // ships its own custom crypto, revisit this and file an ERN.
                "ITSAppUsesNonExemptEncryption": .boolean(false),
            ]),
            sources: ["moodbound/**/*.swift"],
            resources: ["moodbound/Resources/**"],
            entitlements: .file(path: "moodbound/moodbound.entitlements"),
            settings: .settings(base: [
                "DEVELOPMENT_TEAM": "H82APH3TK5",
                "CODE_SIGN_STYLE": "Automatic",
            ])
        ),
        .target(
            name: "moodboundTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.Moodbound.tests",
            deploymentTargets: .iOS("17.0"),
            infoPlist: .default,
            sources: ["moodboundTests/**/*.swift"],
            dependencies: [
                .target(name: "moodbound"),
            ]
        ),
        .target(
            name: "moodboundUITests",
            destinations: .iOS,
            product: .uiTests,
            bundleId: "dev.tuist.Moodbound.uitests",
            deploymentTargets: .iOS("17.0"),
            infoPlist: .default,
            sources: ["moodboundUITests/**/*.swift"],
            dependencies: [
                .target(name: "moodbound"),
            ]
        ),
    ]
)
