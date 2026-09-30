//
//  LearningPersistence.swift
//  LearningPersistence
//
//  La mémoire du module Apprentissage.
//

import Foundation
import LearningKit

/// La mémoire du module Apprentissage.
///
/// Deux objets seulement : le **profil** — ce que l'utilisateur veut apprendre, et à quel rythme —
/// et le **programme** — les passages, avec l'état de chacun. L'historique des séances viendra s'y
/// ajouter.
///
/// Toutes les méthodes sont synchrones. Le magasin est `UserDefaults`, qui répond sans entrée-sortie
/// bloquante pour quelques kilo-octets : une signature `async` n'apporterait ici qu'une propagation
/// de `await` dans les écrans, sans rien rendre plus sûr.
public protocol LearningPersistence: Sendable {
    /// Le profil enregistré, ou un profil vierge si rien n'a encore été configuré.
    func loadProfile() -> LearningProfile

    /// Enregistre un profil.
    ///
    /// Ne touche pas au programme. Une modification du profil doit passer par
    /// `regenerateProgram(for:from:)`, seul chemin qui sache reporter la progression acquise ;
    /// enregistrer le profil seul laisserait un programme qui ne répond plus à ce que l'utilisateur
    /// a demandé.
    func saveProfile(_ profile: LearningProfile)

    /// Le programme enregistré, vide tant qu'il n'a pas été généré.
    func loadProgram() -> LearningProgram

    /// Enregistre un programme — c'est ce qu'appelle le marquage d'un passage, appris ou à revoir.
    func saveProgram(_ program: LearningProgram)

    /// Régénère le programme du profil en reportant la progression déjà acquise, l'enregistre, et
    /// le rend.
    ///
    /// À appeler après toute modification du profil. L'ancien programme est relu ici même, par cette
    /// seule méthode : c'est ce qui garantit qu'aucune régénération ne fait perdre un acquis, sans
    /// dépendre de la vigilance de l'appelant.
    @discardableResult
    func regenerateProgram(for profile: LearningProfile, from date: Date) -> LearningProgram

    /// Efface le profil et le programme — l'utilisateur repart de la configuration guidée.
    func reset()
}
