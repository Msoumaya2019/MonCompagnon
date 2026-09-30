//
//  PreferenceTransformer+JSON.swift
//  Preferences
//
//  Ranger une valeur composée dans les préférences, sous forme de JSON.
//

import Foundation

extension PreferenceTransformer where Raw == Data, T: Codable {
    /// Un transformateur qui range une valeur `Codable` en JSON, dans une clé `Data`.
    ///
    /// Pourquoi une seule clé `Data` plutôt qu'une clé par champ : une valeur composée comme un
    /// profil ou un programme évolue. Éclatée en clés, chaque évolution du modèle obligerait à
    /// migrer les clés, et une lecture partielle — un champ présent, l'autre absent — donnerait un
    /// objet à moitié rempli dont personne ne saurait dire s'il est valide.
    ///
    /// Une donnée illisible — clé absente, contenu tronqué, modèle d'une version antérieure — rend
    /// la valeur par défaut au lieu de lever. Une préférence ne doit jamais faire échouer le
    /// démarrage de l'application : perdre une configuration est ennuyeux, refuser de démarrer ne
    /// l'est pas.
    ///
    /// - Note: la date est encodée par la stratégie par défaut de `JSONEncoder`
    ///   (`.deferredToDate`), soit un nombre de secondes depuis une référence absolue. C'est ce
    ///   qu'il faut pour un format conservé sur l'appareil : ni fuseau horaire, ni calendrier, donc
    ///   aucune ambiguïté à la relecture.
    public static func json(
        defaultValue: @escaping @autoclosure () -> T,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) -> PreferenceTransformer<Data, T> {
        PreferenceTransformer<Data, T>(
            rawToValue: { data in
                guard !data.isEmpty, let value = try? decoder.decode(T.self, from: data) else {
                    return defaultValue()
                }
                return value
            },
            valueToRaw: { value in
                (try? encoder.encode(value)) ?? Data()
            }
        )
    }
}
