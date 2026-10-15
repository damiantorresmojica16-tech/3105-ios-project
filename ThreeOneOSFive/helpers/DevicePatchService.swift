import Foundation

enum DevicePatchService {
    static let configurationCTargetRelativePath =
        "Documents/contentcache/Compulsory/ios/gameassetbundles/avatar/assetindexer.U6Zffc4YIR3DslNj3cXvYGAqz58~3D"
    static let configurationATargetRelativePath =
        "Documents/contentcache/Optional/ios/gameassetbundles/shaders.P0K3UG2TfecMBhWMMV~2Fu8ReudIk~3D"
    static let configurationBTargetRelativePath =
        "Documents/contentcache/Optional/ios/optionalavatarres/gameassetbundles/optionalavatarres_commonab_shader.BNrjwQsbTrqz6jACY9i6FB6DyYI~3D"

    static func apply(project: PatchProject) throws -> PatchTransactionReceipt {
        let bundleIDs = orderedBundleIdentifiers(in: project)
        return try withResolvedContainers(bundleIDs: bundleIDs) { roots in
            try PatchTransaction.apply(
                project: project,
                backupRoot: try PatchProjectLibrary.backupRootURL(),
                containerResolver: { bundleID in
                    guard let root = roots[bundleID] else {
                        throw PatchPackageError.targetAppUnavailable(bundleID)
                    }
                    return root
                }
            )
        }
    }

    static func profileProject(
        from project: PatchProject,
        targetRelativePath: String
    ) throws -> PatchProject {
        guard project.rules.count == 1, let sourceRule = project.rules.first else {
            throw PatchPackageError.invalidProject
        }
        let targetPath = try PatchPathValidator.canonicalRelativePath(targetRelativePath)
        let documentsPrefix = "Documents/"
        guard targetPath.hasPrefix(documentsPrefix),
              targetPath.hasPrefix("Documents/contentcache/"),
              let bundleID = Bundle.main.bundleIdentifier,
              (try? PatchPathValidator.canonicalBundleIdentifier(bundleID)) == bundleID else {
            throw PatchPackageError.invalidProject
        }

        var targetRule = sourceRule
        targetRule.bundleID = bundleID
        targetRule.relativePath = String(targetPath.dropFirst(documentsPrefix.count))
        return PatchProject(
            id: project.id,
            name: project.name,
            author: project.author,
            isPrivate: project.isPrivate,
            createdAt: project.createdAt,
            updatedAt: project.updatedAt,
            bundleIdentifiers: [bundleID],
            directories: [],
            rules: [targetRule]
        )
    }

    static func inspectRestore(receipt: PatchTransactionReceipt) throws -> PatchRestoreInspection {
        let bundleIDs = try PatchTransaction.requiredBundleIdentifiers(for: receipt)
        return try withResolvedContainers(bundleIDs: bundleIDs) { roots in
            try PatchTransaction.inspectRestore(
                receipt: receipt,
                containerResolver: { bundleID in
                    guard let root = roots[bundleID] else {
                        throw PatchPackageError.targetAppUnavailable(bundleID)
                    }
                    return root
                }
            )
        }
    }

    static func restore(
        receipt: PatchTransactionReceipt,
        allowChangedTargets: Bool = false
    ) throws {
        let bundleIDs = try PatchTransaction.requiredBundleIdentifiers(for: receipt)
        try withResolvedContainers(bundleIDs: bundleIDs) { roots in
            try PatchTransaction.restore(
                receipt: receipt,
                allowChangedTargets: allowChangedTargets,
                containerResolver: { bundleID in
                    guard let root = roots[bundleID] else {
                        throw PatchPackageError.targetAppUnavailable(bundleID)
                    }
                    return root
                }
            )
        }
    }

    static func resetToAppliedState(
        receipt: PatchTransactionReceipt,
        project: PatchProject
    ) throws {
        let bundleIDs = try PatchTransaction.requiredBundleIdentifiers(for: receipt)
        try withResolvedContainers(bundleIDs: bundleIDs) { roots in
            try PatchTransaction.resetToAppliedState(
                receipt: receipt,
                fallbackProject: project,
                containerResolver: { bundleID in
                    guard let root = roots[bundleID] else {
                        throw PatchPackageError.targetAppUnavailable(bundleID)
                    }
                    return root
                }
            )
        }
    }

    static func latestReceipt(projectID: UUID) -> PatchTransactionReceipt? {
        guard let backupRoot = try? PatchProjectLibrary.backupRootURL() else { return nil }
        return PatchTransaction.latestReceipt(projectID: projectID, backupRoot: backupRoot)
    }

    private static func orderedBundleIdentifiers(in project: PatchProject) -> [String] {
        project.allBundleIdentifiers
    }

    private static func withResolvedContainers<T>(
        bundleIDs: [String],
        operation: ([String: URL]) throws -> T
    ) throws -> T {
        var roots: [String: URL] = [:]

        for bundleID in bundleIDs {
            if bundleID == Bundle.main.bundleIdentifier {
                do {
                    let documentsURL = try FileManager.default.url(
                        for: .documentDirectory,
                        in: .userDomainMask,
                        appropriateFor: nil,
                        create: true
                    )
                    var isDirectory: ObjCBool = false
                    guard FileManager.default.fileExists(
                        atPath: documentsURL.path,
                        isDirectory: &isDirectory
                    ), isDirectory.boolValue else {
                        throw PatchPackageError.internalDocumentsUnavailable
                    }
                    roots[bundleID] = PatchPathValidator.canonicalFileURL(documentsURL)
                    continue
                } catch let error as PatchPackageError {
                    throw error
                } catch {
                    throw PatchPackageError.internalDocumentsUnavailable
                }
            }
            guard let path = ContainerStore.resolveAppContainerPath(bundleID: bundleID),
                  ContainerStore.isApplicationContainerPath(path) else {
                throw PatchPackageError.targetAppUnavailable(bundleID)
            }
            roots[bundleID] = PatchPathValidator.canonicalFileURL(URL(fileURLWithPath: path, isDirectory: true))
        }
        return try operation(roots)
    }
}
