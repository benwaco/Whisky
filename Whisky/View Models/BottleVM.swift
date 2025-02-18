//
//  BottleVM.swift
//  Whisky
//
//  Created by Isaac Marovitz on 24/03/2023.
//

import Foundation

class BottleVM: ObservableObject {
    static let shared = BottleVM()

    static let containerDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library")
        .appendingPathComponent("Containers")
        .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.isaacmarovitz.Whisky")

    static let bottleDir = containerDir
        .appendingPathComponent("Bottles")

    @Published var bottles: [Bottle] = []
    enum NameFailureReason {
        case emptyName
        case alreadyExists

        var description: String {
            switch self {
            case .emptyName:
                return String(localized: "create.warning.emptyName")
            case .alreadyExists:
                return String(localized: "create.warning.alreadyExistsName")
            }
        }
    }

    enum BottleValidationResult {
        case success
        case failure(reason: NameFailureReason)
    }

    @MainActor
    func loadBottles() {
        bottles.removeAll()

        do {
            let files = try FileManager.default.contentsOfDirectory(at: BottleVM.bottleDir,
                                                                    includingPropertiesForKeys: nil,
                                                                    options: .skipsHiddenFiles)
            for file in files where file.pathExtension == "plist" {
                do {
                    let bottle = try Bottle(settingsURL: file)
                    bottles.append(bottle)
                } catch {
                    print("Failed to load bottle at \(file.path)!")
                }
            }
        } catch {
            print("Failed to load bottles: \(error)")
        }

        bottles.sortByName()
    }

    func createNewBottle(bottleName: String, winVersion: WinVersion, bottleURL: URL) -> URL {
        let newBottleDir = bottleURL.appendingPathComponent(bottleName)
        Task(priority: .userInitiated) {
            do {
                if !FileManager.default.fileExists(atPath: BottleVM.bottleDir.path) {
                    try FileManager.default.createDirectory(atPath: BottleVM.bottleDir.path,
                                                            withIntermediateDirectories: true)
                }

                try FileManager.default.createDirectory(atPath: newBottleDir.path, withIntermediateDirectories: true)

                let settingsURL = BottleVM.bottleDir
                    .appendingPathComponent(bottleName)
                    .appendingPathExtension("plist")

                let bottle = Bottle(settingsURL: settingsURL,
                                    bottleURL: newBottleDir,
                                    inFlight: true)
                bottles.append(bottle)
                bottles.sortByName()

                bottle.settings.windowsVersion = winVersion
                try await Wine.changeWinVersion(bottle: bottle, win: winVersion)
                bottle.settings.wineVersion = try await Wine.wineVersion()
                await loadBottles()
            } catch {
                print("Failed to create new bottle")
            }
        }
        return newBottleDir
    }

    func isValidBottleName(bottleName: String) -> BottleValidationResult {
        if bottleName.isEmpty {
            return BottleValidationResult.failure(reason: NameFailureReason.emptyName)
        }

        if bottles.contains(where: {$0.name == bottleName}) {
            return BottleValidationResult.failure(reason: NameFailureReason.alreadyExists)
        }
        return BottleValidationResult.success
    }
}
