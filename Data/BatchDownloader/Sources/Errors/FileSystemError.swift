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
    /// L'écriture a été refusée faute de place.
    ///
    /// `availableBytes` porte l'espace encore libre au moment de l'échec. Sans ce chiffre, « le
    /// disque est plein » et « l'écriture a été refusée pour une autre raison » ne se distinguent
    /// pas dans une capture d'écran — or c'est exactement la question à trancher.
    case noDiskSpace(availableBytes: Int64?)
    case unknown(Error)

    // MARK: Lifecycle

    public init(error: Error) {
        switch error {
        case let cocoaError as CocoaError where cocoaError.code == .fileWriteOutOfSpace:
            self = .noDiskSpace(availableBytes: nil)
        case let urlError as URLError where urlError.code == .cannotCreateFile:
            // iOS dit « Impossible de créer le fichier » — `NSURLErrorCannotCreateFile`, code
            // `-3000` — là où le disque est plein. Ce code n'était reconnu nulle part : il tombait
            // dans `.unknown`, et le message qui nomme la cause restait hors d'atteinte. C'est
            // pourtant celui que le gestionnaire de téléchargement remonte réellement.
            self = .noDiskSpace(availableBytes: nil)
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
        case .noDiskSpace(let availableBytes):
            Self.describeNoDiskSpace(availableBytes)
        }
        return text
    }

    /// « Pas d'espace disque disponible… (1,2 Go libres) ».
    ///
    /// Le chiffre rend le message vérifiable : sans lui, on ne peut pas dire depuis une capture
    /// d'écran si l'appareil était réellement à court de place.
    private static func describeNoDiskSpace(_ availableBytes: Int64?) -> String {
        let message = l("error.message.no_disk_space")
        guard let availableBytes else {
            return message
        }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return "\(message) (\(formatter.string(fromByteCount: availableBytes)))"
    }

    /// « NSCocoaErrorDomain 4 », pour nommer l'erreur au lieu de la taire.
    private static func identify(_ error: Error) -> String {
        let nsError = error as NSError
        return "\(nsError.domain) \(nsError.code)"
    }
}
