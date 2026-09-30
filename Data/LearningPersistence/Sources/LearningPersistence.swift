//
//  LearningPersistence.swift
//  LearningPersistence
//
//  La mémoire du module Apprentissage.
//

import Foundation
import LearningKit
import QuranKit

/// La mémoire du module Apprentissage.
///
/// Trois objets : le **profil** — ce que l'utilisateur veut apprendre, et à quel rythme —, le
/// **programme** — les passages, avec l'état de chacun — et le **relevé de progression** — ce qui a
/// réellement été appris, sourate par sourate. L'historique des séances viendra s'y ajouter.
///
/// Toutes les méthodes sont synchrones. Le magasin est `UserDefaults`, qui répond sans entrée-sortie
/// bloquante pour quelques kilo-octets : une signature `async` n'apporterait ici qu'une propagation
/// de `await` dans les écrans, sans rien rendre plus sûr.
public protocol LearningPersistence: Sendable {
    /// Le mushaf de référence du magasin.
    ///
    /// L'interface en a besoin pour compter les versets et composer les libellés. Le lui faire
    /// deviner — un mushaf par défaut écrit dans la vue — laisserait deux mushafs coexister, et
    /// l'écran annoncerait alors des tailles qui ne seraient pas celles du programme.
    var quran: Quran { get }

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
    ///
    /// Met aussi à jour le relevé de progression, qui est le reflet de ce que le programme porte.
    func saveProgram(_ program: LearningProgram)

    /// Le relevé de progression enregistré, vide tant que rien n'a été appris.
    func loadProgress() -> LearningProgress

    /// Enregistre un relevé de progression.
    ///
    /// Le relevé **fusionne** avec celui déjà enregistré : la progression ne recule jamais. C'est ce
    /// qui fait survivre l'avancement d'un objectif qui quitte le programme, et qui permet de le
    /// rajouter plus tard sans repartir de zéro — la seule perte silencieuse que ce module puisse
    /// causer.
    func saveProgress(_ progress: LearningProgress)

    /// Régénère le programme du profil en reportant la progression déjà acquise, l'enregistre, et
    /// le rend.
    ///
    /// À appeler après toute modification du profil. L'ancien programme est relu ici même, par cette
    /// seule méthode : c'est ce qui garantit qu'aucune régénération ne fait perdre un acquis, sans
    /// dépendre de la vigilance de l'appelant.
    @discardableResult
    func regenerateProgram(for profile: LearningProfile, from date: Date) -> LearningProgram

    /// Efface le profil, le programme et le relevé — l'utilisateur repart de la configuration guidée.
    func reset()
}
