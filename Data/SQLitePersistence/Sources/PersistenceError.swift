//
//  PersistenceError.swift
//  Quran
//
//  Created by Mohamed Afifi on 4/22/16.
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

public enum PersistenceError: Error {
    case general(String)
    case openDatabase(Error, filePath: String)
    case query(Error)
    case unknown(Error)
    case badFile(Error?)

    // MARK: Public

    public static func generalError(_ error: Error, info: String) -> PersistenceError {
        .general("error: \(error), info: \(info)")
    }
}

extension PersistenceError: LocalizedError {
    /// Le message à montrer, avec de quoi savoir **ce qui** a échoué.
    ///
    /// Toutes les variantes rendaient le même message, sans exception : une base impossible à
    /// ouvrir, une requête refusée et un fichier de base corrompu étaient indiscernables à
    /// l'écran. On accole donc le détail que porte la variante, ou l'identité de l'erreur
    /// d'origine — domaine et code.
    public var errorDescription: String? {
        "\(l("error.message.general")) (\(detail))"
    }

    private var detail: String {
        switch self {
        case .general(let info):
            return info
        case .openDatabase(let error, let filePath):
            return "\(Self.identify(error)) — \(filePath)"
        case .query(let error), .unknown(let error):
            return Self.identify(error)
        case .badFile(let error):
            guard let error else {
                return "fichier de base illisible"
            }
            return Self.identify(error)
        }
    }

    /// « SQLite.SQLiteError 11 », pour nommer l'erreur au lieu de la taire.
    private static func identify(_ error: Error) -> String {
        let nsError = error as NSError
        return "\(nsError.domain) \(nsError.code)"
    }
}
