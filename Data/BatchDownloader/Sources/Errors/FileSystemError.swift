//
//  FileSystemError.swift
//  Quran
//
//  Created by Mohamed Afifi on 5/14/16.
//
//  Quran for iOS is a Quran reading application for iOS.
//  Copyright (C) 2017  Quran.com
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//

import Foundation
import Localization

public enum FileSystemError: Error {
    /// Le disque est plein — le système l'a dit lui-même, par `ENOSPC` ou `fileWriteOutOfSpace`.
    ///
    /// Ce cas est réservé à ce que le système **nomme**. Un « Impossible de créer le fichier » —
    /// `NSURLErrorCannotCreateFile`, code `-3000` — n'en fait pas partie : il dit qu'écrire a
    /// échoué, sans dire pourquoi. L'y ranger a fait annoncer « pas d'espace disque » sur un
    /// appareil qui avait 17 Go de libre, et a donc envoyé la recherche du côté du disque.
    case noDiskSpace
    case unknown(Error)

    // MARK: Lifecycle

    public init(error: Error) {
        switch error {
        case let cocoaError as CocoaError where cocoaError.code == .fileWriteOutOfSpace:
            self = .noDiskSpace
        default:
            self = .unknown(error)
        }
    }
}

extension FileSystemError: LocalizedError {
    /// Le message à montrer, avec de quoi savoir **ce qui** a échoué.
    ///
    /// `.unknown` recouvre tout ce qui n'est pas un disque plein — un dossier non créé, un
    /// déplacement refusé, un fichier illisible. Le message générique seul ne les distingue pas :
    /// on y accole donc le domaine et le code de l'erreur d'origine, faute de quoi aucune capture
    /// d'écran ne permet de la diagnostiquer.
    public var errorDescription: String? {
        let text: String = switch self {
        case .unknown(let underlying):
            "\(l("error.message.general")) (\(Self.identify(underlying)))"
        case .noDiskSpace:
            l("error.message.no_disk_space")
        }
        return text
    }

    /// « NSCocoaErrorDomain 4 », pour nommer l'erreur au lieu de la taire.
    private static func identify(_ error: Error) -> String {
        let nsError = error as NSError
        return "\(nsError.domain) \(nsError.code)"
    }
}
