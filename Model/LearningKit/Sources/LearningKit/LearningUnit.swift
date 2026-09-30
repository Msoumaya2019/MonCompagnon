//
//  LearningUnit.swift
//  LearningKit
//
//  L'unité dans laquelle on désigne un morceau du Coran.
//

import Foundation

/// L'unité dans laquelle on désigne un morceau du Coran à apprendre.
///
/// Trois mailles, et ce sont celles dont un utilisateur parle : « je connais cette sourate », « j'ai
/// appris ce hizb », « je reprends ce juz' ».
///
/// - Note: à ne pas confondre avec `QuranUnit`, qui sert à **mesurer** une quantité en choisissant
///   la plus grande unité qui la divise exactement. La page et le quart y ont leur place ; ici, non
///   : personne ne dit « je connais la page 312 », et une unité de choix qui ne se dit pas ne sert
///   à rien.
public enum LearningUnit: String, CaseIterable, Sendable {
    /// Les 114 sourates.
    case sourate
    /// Les 60 hizb — un demi-juz'.
    case hizb
    /// Les 30 juz'.
    case juz
}
