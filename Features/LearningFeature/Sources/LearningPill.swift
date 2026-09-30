//
//  LearningPill.swift
//  LearningFeature
//
//  Une pastille qui désigne un morceau du Coran, et qu'on retire d'un geste.
//

import Localization
import NoorUI
import SwiftUI
import UIx

/// Une pastille qui désigne un morceau du Coran, et qu'on retire d'un geste.
///
/// Le ✕ est un **bouton**, et non un ornement : c'est le seul moyen de défaire une déclaration sans
/// reparcourir la liste des morceaux pour retrouver celui qu'on a coché. Sans lui, une erreur de
/// choix se paierait d'une recherche.
struct LearningPill: View {
    /// Ce que la pastille annonce — et donc la couleur qui la distingue des autres.
    enum Tone {
        /// Un objectif à apprendre.
        case goal
        /// Un acquis qu'on récite sans hésiter.
        case solide
        /// Un acquis qu'on oublie.
        case fragile

        // MARK: Internal

        var background: Color {
            switch self {
            case .goal: return Color.accentColor.opacity(0.15)
            case .solide: return Color(uiColor: .secondarySystemBackground)
            case .fragile: return Color(uiColor: .systemYellow).opacity(0.25)
            }
        }

        var foreground: Color {
            switch self {
            case .goal: return .accentColor
            case .solide, .fragile: return Color(uiColor: .label)
            }
        }
    }

    let title: String
    let tone: Tone

    /// Le geste qui retire la déclaration.
    ///
    /// Un `Action`, et non un `() -> Void` : l'écran est isolé sur l'acteur principal, et une
    /// fermeture non isolée ne pourrait pas y toucher. C'est le type que le dépôt emploie déjà pour
    /// porter un geste d'interface — voir `NoorListItem.TapAction`.
    let remove: Action

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.subheadline)
                .lineLimit(1)
                .truncationMode(.tail)

            Button(action: remove) {
                NoorSystemImage.cancel.image
                    .font(.caption2.bold())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(l("learning.pill.remove", table: .learning))
        }
        .foregroundStyle(tone.foreground)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(tone.background))
    }
}
