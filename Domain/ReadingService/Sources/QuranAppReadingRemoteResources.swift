//
//  QuranAppReadingRemoteResources.swift
//  ReadingService
//
//  Où l'application trouve les mushafs qu'elle n'embarque pas.
//
//  Raison d'être : l'application n'embarque qu'un seul mushaf, le Madani 1405. Les autres
//  lectures sont des archives téléchargées à la demande, mais cette application ne savait plus
//  où les prendre — `remoteResources` valait `nil`, si bien qu'aucun mushaf autre que celui du
//  paquet ne pouvait être obtenu, et que le sélecteur de lectures proposait des mushafs
//  impossibles à afficher.
//
//  L'hôte est fourni par l'application plutôt que fixé ici : c'est déjà lui qui sert l'audio
//  des récitateurs (`filesAppHost`), et il ne doit exister qu'à un seul endroit. Les chemins,
//  eux, sont ceux de l'application d'origine, relevés dans son binaire ; la version est celle
//  que porte l'archive elle-même — les marqueurs `.vN` qu'elle contient indiquent la version du
//  jeu de données qu'attend l'application.
//

import Foundation
import QuranKit

public struct QuranAppReadingRemoteResources: ReadingRemoteResources {
    // MARK: Lifecycle

    public init(baseURL: URL) {
        self.baseURL = baseURL
    }

    // MARK: Public

    /// L'archive à télécharger pour une lecture, ou `nil` si l'application ne la propose pas.
    ///
    /// Une lecture absente de la table n'est ni embarquée, ni téléchargeable : le sélecteur de
    /// lectures ne la propose donc pas. C'est la table qui décide de ce que l'application offre
    /// réellement, et non la liste des lectures connues du modèle.
    public func resource(for reading: Reading) -> RemoteResource? {
        guard let archive = Self.archives[reading] else {
            // Aucune archive pour cette lecture : le mushaf Madani 1405 est embarqué dans le
            // paquet, et les mushafs écartés n'ont pas d'adresse. Dans les deux cas, il n'y a
            // rien à télécharger — et c'est ce `nil` qui les retire du sélecteur.
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
    /// Seul le Tajweed y figure : l'application ne propose que le mushaf du paquet et celui-ci.
    /// Les autres mushafs de l'application d'origine (Madani 1421, 1439, 1440 et 1441, Naskh
    /// IndoPak) sont donc ni proposés, ni téléchargeables. Les remettre consisterait à ajouter
    /// leur ligne ici — leurs adresses sont celles de l'application d'origine.
    private static let archives: [Reading: Archive] = [
        .tajweed: Archive(path: "hafs/tajweed/zips/images_1280.zip", version: 7),
    ]

    private let baseURL: URL
}
