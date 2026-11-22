import Foundation
import SwiftData

/// Crée la base SwiftData de l'app.
public enum PersistenceStack {
    /// Base sur disque, dans Application Support, ou en mémoire pour les tests et les aperçus.
    @MainActor
    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else {
            configuration = ModelConfiguration(schema: schema, url: try storeURL())
        }
        return try ModelContainer(for: schema, migrationPlan: NocturneMigrationPlan.self, configurations: [configuration])
    }

    /// Emplacement de la base, protégé « jusqu'au premier déverrouillage »
    /// pour rester inscriptible la nuit, écran verrouillé.
    public static func storeURL() throws -> URL {
        let folder = try applicationSupportFolder(named: "Database")
        return folder.appendingPathComponent("Nocturne.store")
    }

    /// Dossier de l'app dans Application Support, créé au besoin avec la bonne protection.
    public static func applicationSupportFolder(named name: String) throws -> URL {
        let manager = FileManager.default
        let support = try manager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let folder = support.appendingPathComponent(name, isDirectory: true)
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        #if os(iOS)
        try manager.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: folder.path)
        #endif
        return folder
    }
}
