//
//  MissingReadingResourcesView.swift
//  QuranImageFeature
//
//  Affiché quand les images de la lecture choisie ne sont pas présentes sur l'appareil.
//
//  Sans cette vue, l'absence de ressources fermait l'application au moment d'ouvrir le Mushaf.
//  Afficher un message laisse l'utilisateur revenir au sélecteur pour choisir un mushaf
//  réellement disponible.
//

import Localization
import NoorUI
import QuranKit
import SwiftUI

struct MissingReadingResourcesView: View {
    // MARK: Internal

    let reading: Reading

    var body: some View {
        NoorListEmptyState(
            title: l("error.dialog.title"),
            text: l("error.message.general"),
            image: .download,
            style: .prominent(imageColor: .accentColor)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("missing-reading-resources")
    }
}
