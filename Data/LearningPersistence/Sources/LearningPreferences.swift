//
//  LearningPreferences.swift
//  LearningPersistence
//
//  Le profil et le programme d'apprentissage, rangés dans les préférences de l'appareil.
//

import Foundation
import LearningKit
import Preferences

/// Le profil et le programme d'apprentissage, tels qu'ils sont conservés sur l'appareil.
///
/// Chacun tient dans **une seule clé**, en JSON. Une clé par champ obligerait à migrer les clés à
/// chaque évolution du modèle, et une lecture partielle — un champ écrit, l'autre non — donnerait
/// un profil à moitié rempli dont personne ne saurait dire s'il est valide.
///
/// Le contenu illisible rend la valeur par défaut plutôt que de lever : une préférence ne doit
/// jamais empêcher l'application de démarrer.
public struct LearningPreferences {
    // MARK: Lifecycle

    private init() {}

    // MARK: Public

    public static let shared = LearningPreferences()

    /// Le profil d'apprentissage.
    ///
    /// `$profile` publie chaque changement : c'est le point d'entrée des écrans qui doivent réagir à
    /// une modification du profil.
    @TransformedPreference(profile, transformer: .json(defaultValue: LearningProfile.empty))
    public var profile: LearningProfile

    /// Le programme d'apprentissage, avec l'état de chaque passage.
    ///
    /// `$program` publie chaque changement, y compris le marquage d'un passage.
    @TransformedPreference(program, transformer: .json(defaultValue: LearningProgram.empty))
    public var program: LearningProgram

    // MARK: Private

    private static let profile = PreferenceKey<Data>(key: "learningProfile", defaultValue: Data())
    private static let program = PreferenceKey<Data>(key: "learningProgram", defaultValue: Data())
}
