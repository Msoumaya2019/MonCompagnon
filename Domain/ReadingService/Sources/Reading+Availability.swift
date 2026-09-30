//
//  Reading+Availability.swift
//  ReadingService
//
//  Détermine si les images d'une lecture sont réellement présentes sur cet appareil.
//
//  Raison d'être : le service de ressources supposait qu'une lecture sans ressource distante
//  était forcément embarquée dans l'application, et la déclarait donc « prête ». C'est vrai de
//  l'application Quran.com, qui embarque tous les mushafs, mais pas d'une application qui n'en
//  embarque qu'un. Choisir une lecture absente menait alors à ouvrir un dossier d'images
//  inexistant, ce qui fermait l'application.
//

import Foundation
import QuranKit
import Utilities

extension Reading {
    // MARK: Public

    /// Vrai si les images de cette lecture sont embarquées dans l'application.
    ///
    /// Le nom du dossier est `localPath`, exactement comme pour les ressources téléchargées :
    /// les deux chemins ne peuvent donc pas diverger.
    public var isBundled: Bool {
        Bundle.main.url(forResource: localPath, withExtension: nil) != nil
    }

    /// Vrai si les images de cette lecture ont déjà été téléchargées sur cet appareil.
    public var isDownloaded: Bool {
        let directory = Self.readingsPath.appendingPathComponent(localPath, isDirectory: true)
        return FileManager.default.fileExists(atPath: directory.url.path)
    }

    /// Vrai si cette lecture peut réellement être affichée sur cet appareil.
    ///
    /// Ni embarquée ni téléchargée signifie qu'il n'y a aucune image à montrer. Mieux vaut le
    /// savoir avant d'ouvrir le Mushaf que de le découvrir en le fermant.
    public var isAvailable: Bool {
        isBundled || isDownloaded
    }

    /// Vrai si cette lecture peut être obtenue sur cet appareil.
    ///
    /// Embarquée, déjà téléchargée, ou téléchargeable : dans les trois cas elle a une raison
    /// d'être proposée. Une lecture téléchargeable mais pas encore téléchargée doit rester dans
    /// la liste, car c'est en la choisissant qu'on déclenche son téléchargement ; la masquer la
    /// rendrait définitivement inaccessible.
    ///
    /// `isAvailable`, elle, répond à une autre question — « y a-t-il des images à afficher
    /// maintenant ? » — et sert à choisir la lecture de repli, pas à composer la liste.
    public func isObtainable(remoteResources: ReadingRemoteResources?) -> Bool {
        isAvailable || remoteResources?.resource(for: self) != nil
    }

    /// La lecture à utiliser pour l'affichage, en partant de celle qui est enregistrée.
    ///
    /// Renvoie la lecture demandée si elle est utilisable, sinon la première lecture disponible
    /// sur cet appareil. Aucune donnée n'est modifiée : le réglage enregistré reste intact, seul
    /// l'affichage s'adapte à ce que l'appareil possède réellement.
    public static func available(_ preferred: Reading) -> Reading {
        guard !preferred.isAvailable else { return preferred }
        return allReadings.first(where: \.isAvailable) ?? preferred
    }
}
