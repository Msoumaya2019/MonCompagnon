//
//  Localizations.swift
//  Quran
//
//  Created by Mohamed Afifi on 4/13/18.
//
//  Quran for iOS is a Quran reading application for iOS.
//  Copyright (C) 2018  Quran.com
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

public enum Language: String {
    case arabic = "ar"
    case english = "en"
}

public enum Table: String {
    case localizable = "Localizable"
    case android = "Android"
    case suras = "Suras"
    case readers = "Readers"
    /// Les libellés de l'espace d'apprentissage.
    ///
    /// Table à part, et non `Localizable`, pour une raison précise : `LocalizationCatalogTests`
    /// impose que **toutes** les langues aient exactement les mêmes clés que l'anglais dans
    /// `Localizable.strings`. Une table par usage, comme `Readers` et `Suras`, n'a pas cette
    /// contrainte : une langue absente retombe sur l'anglais, et l'espace peut être traduit
    /// langue par langue sans bloquer le reste.
    case learning = "Learning"
}

public func lFormat(_ key: String, table: Table = .localizable, language: Language? = nil, _ arguments: CVarArg...) -> String {
    let localization = l(key, table: table, language: language)
    return String(format: localization, locale: .fixedCurrentLocaleNumbers, arguments: arguments)
}

public func l(_ key: String, table: Table = .localizable, language: Language? = nil) -> String {
    if let language {
        return localizedString(key, table: table, language: language)
    }
    let value = NSLocalizedString(key, tableName: table.rawValue, bundle: Bundle.fixedModule, comment: "")
    if value != key || Locale.preferredLanguageLocale.languageCode == Language.english.rawValue {
        return value
    }

    // Fall back to en
    return localizedString(key, table: table, language: .english)
}

private func localizedString(_ key: String, table: Table = .localizable, language: Language) -> String {
    guard
        let path = Bundle.fixedModule.path(forResource: language.rawValue, ofType: "lproj"),
        let bundle = Bundle(path: path)
    else { return key }
    return NSLocalizedString(key, tableName: table.rawValue, bundle: bundle, comment: "")
}

public func lAndroid(_ key: String, language: Language? = nil) -> String {
    l(key, table: .android, language: language)
}
