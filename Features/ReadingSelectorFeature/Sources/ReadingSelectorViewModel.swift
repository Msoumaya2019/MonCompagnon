//
//  ReadingSelectorViewModel.swift
//  Quran
//
//  Created by Mohamed Afifi on 2023-02-14.
//  Copyright © 2023 Quran.com. All rights reserved.
//

import Foundation
import Localization
import NoorUI
import QuranKit
import ReadingService

@MainActor
class ReadingSelectorViewModel: ObservableObject {
    // MARK: Lifecycle

    init(resources: ReadingResourcesService, remoteResources: ReadingRemoteResources?) {
        self.resources = resources
        self.remoteResources = remoteResources
    }

    // MARK: Internal

    @Published var selectedReading: Reading?
    @Published var progress: Double?
    @Published var error: Error?

    var readingGroups: [ReadingGroup<Reading>] {
        [
            ReadingGroup(
                id: "uthmani",
                title: l("reading.selector.group.uthmani"),
                readings: [
                    .hafs_1405,
                    .hafs_1441,
                    .hafs_1440,
                    .hafs_1439,
                    .hafs_1421,
                ].map(ReadingInfo.init)
            ),
            ReadingGroup(
                id: "tajweed",
                title: l("reading.selector.group.tajweed"),
                readings: [Reading.tajweed].map(ReadingInfo.init)
            ),
            ReadingGroup(
                id: "indopak",
                title: l("reading.selector.group.indopak"),
                readings: [Reading.indoPak].map(ReadingInfo.init)
            ),
        ]
        // Seuls les mushafs que l'appareil peut réellement obtenir sont proposés : ceux du
        // paquet, ceux déjà téléchargés, et ceux que l'application sait télécharger. Proposer
        // les autres laissait choisir un mushaf qui ne pouvait pas s'afficher.
        .compactMap { group in
            let readings = group.readings.filter(isObtainable)
            guard !readings.isEmpty else { return nil }
            return ReadingGroup(id: group.id, title: group.title, readings: readings)
        }
    }

    func start() async {
        async let reading: () = listenToReadingChanges()
        async let resources: () = listenToResourcesEvents()
        _ = await (reading, resources)
    }

    func showReading(_ reading: Reading) {
        preferences.reading = reading
    }

    // MARK: Private

    private let preferences = ReadingPreferences.shared
    private let resources: ReadingResourcesService
    private let remoteResources: ReadingRemoteResources?

    /// Une lecture proposée est une lecture que l'appareil peut obtenir : du paquet, déjà
    /// téléchargée, ou téléchargeable. Voir `Reading.isObtainable(remoteResources:)`.
    private func isObtainable(_ reading: ReadingInfo<Reading>) -> Bool {
        reading.value.isObtainable(remoteResources: remoteResources)
    }

    private func listenToReadingChanges() async {
        let readingsSequence = preferences.$reading
            .prepend(preferences.reading)
            .values()
        for await reading in readingsSequence {
            // On coche la lecture choisie dès lors qu'elle est proposée — y compris pendant son
            // téléchargement, sinon la coche reviendrait sur un autre mushaf le temps du
            // transfert. Une lecture enregistrée qui n'est plus proposée retombe sur la première
            // lecture affichable : sans cela, aucune ligne ne serait cochée.
            if reading.isObtainable(remoteResources: remoteResources) {
                selectedReading = reading
            } else {
                selectedReading = Reading.available(reading)
            }
        }
    }

    private func listenToResourcesEvents() async {
        let resourceStatuses = resources.publisher.values()
        for await status in resourceStatuses {
            switch status {
            case .downloading(let progress):
                self.progress = progress
                error = nil
            case .error(let error):
                progress = nil
                self.error = error
            case .ready:
                progress = nil
                error = nil
            }
        }
    }
}

private extension ReadingInfo where Value == Reading {
    init(_ reading: Reading) {
        let tags: [NoorTag] = switch reading {
        case .hafs_1441, .hafs_1439:
            [NoorTag(
                title: l("reading.selector.badge.large-screen-optimized"),
                tone: .accent
            )]
        case .indoPak:
            [NoorTag(
                title: l("reading.selector.badge.experimental"),
                tone: .red
            )]
        default:
            []
        }

        self.init(
            value: reading,
            title: reading.title,
            description: reading.description,
            properties: reading.properties,
            tags: tags
        )
    }
}
