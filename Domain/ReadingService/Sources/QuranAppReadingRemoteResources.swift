//
//  QuranAppReadingRemoteResources.swift
//  ReadingService
//
//  Où l'application trouverait les mushafs qu'elle n'embarque pas.
//
//  Cette table est aujourd'hui **vide**, et c'est voulu : l'application embarque ses deux
//  mushafs, le Madani 1405 et le Tajweed. Le type reste néanmoins la seule description de
//  l'endroit où une lecture non embarquée se téléchargerait, et il porte l'adresse vérifiée du
//  Tajweed pour que le jour où l'on voudra alléger l'application, il n'y ait qu'une ligne à
//  rétablir.
//
//  Adresse mesurée sur le serveur le 30 septembre 2026 :
//
//      https://files.quran.app/hafs/tajweed/zips/images_1280.zip
//      143 688 256 octets, `application/zip`, 617 entrées, archive ZIP standard (méthodes 0 et 8)
//      contenu : width_1280/page001.png … page604.png, width_1280/.v7, databases/ayahinfo_1280.db
//
//  Elle a servi à embarquer le mushaf ; elle n'est plus appelée au lancement, car une lecture
//  embarquée n'a rien à télécharger.
//
//  L'hôte est fourni par l'application plutôt que fixé ici : c'est déjà lui qui sert l'audio des
//  récitateurs (`filesAppHost`), et il ne doit exister qu'à un seul endroit.
//

import Foundation
import QuranKit

public struct QuranAppReadingRemoteResources: ReadingRemoteResources {
    // MARK: Lifecycle

    public init(baseURL: URL) {
        self.baseURL = baseURL
    }

    // MARK: Public

    /// L'archive à télécharger pour une lecture, ou `nil` si l'application ne la télécharge pas.
    ///
    /// Une lecture absente de la table n'est pas téléchargeable. Si elle est embarquée dans le
    /// paquet, elle est proposée ; sinon, le sélecteur de lectures ne la propose pas. C'est donc
    /// cette table qui décide de ce que l'application peut **obtenir**, et non la liste des
    /// lectures connues du modèle.
    public func resource(for reading: Reading) -> RemoteResource? {
        guard let archive = Self.archives[reading] else {
            // Rien à télécharger : la lecture est soit embarquée, soit écartée. C'est ce `nil`
            // qui la retire du sélecteur si elle n'est pas embarquée.
            return nil
        }
        return RemoteResource(
            url: baseURL.appendingPathComponent(archive.path),
            reading: reading,
            version: archive.version,
            ayahMarkerURL: nil
        )
    }

    // MARK: Private

    private struct Archive {
        let path: String
        let version: Int
    }

    /// Les lectures que l'application sait télécharger.
    ///
    /// Vide : les deux mushafs proposés sont dans le paquet. Ajouter une ligne ici suffirait à
    /// rendre une lecture téléchargeable — à condition qu'elle ne soit **pas** embarquée, sinon
    /// l'application la téléchargerait sans raison, et c'est le paquet qui doit l'emporter.
    ///
    /// Pour mémoire, les adresses des mushafs de l'application d'origine sont, sous le même hôte :
    /// `hafs/madani_1440/zips/images_1352.zip`, `hafs/madani_1421/zips/images_1120.zip`,
    /// `hafs/madani_1439/zips/images_1080.zip`, `hafs/madani_1441/zips/images_1440.zip` et
    /// `hafs/naskh_kingfahd/zips/images_1342.zip`.
    private static let archives: [Reading: Archive] = [:]

    private let baseURL: URL
}
