//
//  LearningDirection.swift
//  LearningKit
//
//  Dans quel sens le programme parcourt le mushaf.
//

import Foundation

/// Le sens dans lequel le programme parcourt le mushaf.
///
/// Le sens ne décide pas de **ce qui** est programmé — c'est l'affaire des objectifs — mais de
/// **par quel bout** on commence, et donc de l'ordre des séances. Un objectif qui couvre plusieurs
/// sourates se lit d'un bout ou de l'autre.
///
/// Chaque cas porte le nom de ce par quoi l'on commence, parce que c'est ainsi qu'un utilisateur en
/// parle : « je pars d'An-Nas », « je pars d'Al-Baqarah ».
///
/// - Note: `.depuisLeDebut` est le **repli des profils enregistrés avant ce réglage**. Il décrit
///   exactement le seul comportement qui existait alors — l'ordre du mushaf — donc leur programme
///   ne change pas d'un verset.
public enum LearningDirection: String, Codable, CaseIterable, Sendable {
    /// L'ordre du mushaf : Al-Fatiha, Al-Baqarah, Âl-Imrân… jusqu'à An-Nas.
    case depuisLeDebut

    /// Le mushaf à rebours : An-Nas, Al-Falaq, Al-Ikhlas… jusqu'à Al-Fatiha.
    ///
    /// C'est le sens des mémorisations commencées par la fin, où l'on consolide les sourates
    /// courtes avant d'aborder les longues.
    case depuisLaFin

    // MARK: Public

    /// Vrai si les séances se suivent dans l'ordre décroissant du mushaf.
    public var isDescending: Bool { self == .depuisLaFin }
}
