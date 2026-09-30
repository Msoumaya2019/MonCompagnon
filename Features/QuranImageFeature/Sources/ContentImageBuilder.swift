//
//  ContentImageBuilder.swift
//  Quran
//
//  Created by Afifi, Mohamed on 9/16/19.
//  Copyright © 2019 Quran.com. All rights reserved.
//

import AnnotationsService
import AppDependencies
import Foundation
import ImageService
import QuranKit
import QuranPagesFeature
import ReadingService
import SwiftUI
import UIKit
import Utilities
import VLogging

@MainActor
public struct ContentImageBuilder {
    // MARK: Lifecycle

    public init(container: AppDependencies, overlayService: VerseOverlayService) {
        self.container = container
        self.overlayService = overlayService
    }

    // MARK: Public

    #if QURAN_SYNC
    @ViewBuilder
    public func build(
        at page: Page,
        onAnnotatedAyahTap: @escaping (AyahNumber, CGPoint) -> Void
    ) -> some View {
        let reading = Self.reading()
        if reading.usesLinePages {
            if let linePageAssetService = Self.buildLinePageAssetService(reading: reading, container: container) {
                let viewModel = ContentLineViewModel(
                    reading: reading,
                    page: page,
                    linePageAssetService: linePageAssetService,
                    overlayService: overlayService
                )
                ContentLineView(
                    viewModel: viewModel,
                    onAnnotatedAyahTap: onAnnotatedAyahTap
                )
            } else {
                MissingReadingResourcesView(reading: reading)
            }
        } else {
            if let imageService = Self.buildImageDataService(reading: reading, container: container) {
                let viewModel = ContentImageViewModel(
                    reading: reading,
                    page: page,
                    imageDataService: imageService,
                    overlayService: overlayService
                )
                ContentImageView(
                    viewModel: viewModel,
                    onAnnotatedAyahTap: onAnnotatedAyahTap
                )
            } else {
                MissingReadingResourcesView(reading: reading)
            }
        }
    }

    #else
    @ViewBuilder
    public func build(at page: Page) -> some View {
        let reading = Self.reading()
        if reading.usesLinePages {
            if let linePageAssetService = Self.buildLinePageAssetService(reading: reading, container: container) {
                let viewModel = ContentLineViewModel(
                    reading: reading,
                    page: page,
                    linePageAssetService: linePageAssetService,
                    overlayService: overlayService
                )
                ContentLineView(viewModel: viewModel)
            } else {
                MissingReadingResourcesView(reading: reading)
            }
        } else {
            if let imageService = Self.buildImageDataService(reading: reading, container: container) {
                let viewModel = ContentImageViewModel(
                    reading: reading,
                    page: page,
                    imageDataService: imageService,
                    overlayService: overlayService
                )
                ContentImageView(viewModel: viewModel)
            } else {
                MissingReadingResourcesView(reading: reading)
            }
        }
    }

    #endif

    // MARK: Internal

    /// La lecture à afficher : celle qui est enregistrée, ou à défaut une lecture réellement
    /// présente sur l'appareil.
    ///
    /// Une lecture choisie dans le sélecteur peut n'avoir ni images embarquées ni images
    /// téléchargées. Sans ce repli, ouvrir le Mushaf demandait un dossier d'images absent et
    /// fermait l'application. Le réglage enregistré n'est pas modifié : seul l'affichage s'adapte.
    static func reading() -> Reading {
        let preferred = ReadingPreferences.shared.reading
        let resolved = Reading.available(preferred)
        if resolved != preferred {
            logger.error("Images: Reading \(preferred) has no images on this device; using \(resolved)")
        }
        return resolved
    }

    static func buildImageDataService(reading: Reading, container: AppDependencies) -> ImageDataService? {
        guard let readingDirectory = Self.readingDirectory(reading, container: container) else {
            return nil
        }
        return ImageDataService(
            ayahInfoDatabase: reading.ayahInfoDatabase(in: readingDirectory),
            imagesURL: reading.imagesDirectory(in: readingDirectory),
            ayahMarkerURL: container.remoteResources?.resource(for: reading)?.ayahMarkerURL
        )
    }

    static func buildLinePageAssetService(reading: Reading, container: AppDependencies) -> LinePageAssetService? {
        guard let metrics = reading.linePageMetrics else {
            logger.error("Images: Attempted to build line-page assets for non-line-page reading \(reading)")
            return nil
        }
        guard let readingDirectory = Self.readingDirectory(reading, container: container) else {
            return nil
        }
        return LinePageAssetService(
            readingDirectory: readingDirectory,
            metrics: metrics,
            quran: reading.quran,
            ayahMarkerURL: container.remoteResources?.resource(for: reading)?.ayahMarkerURL
        )
    }

    /// Le dossier d'images d'une lecture, ou `nil` si l'appareil n'en possède aucune.
    ///
    /// L'ordre compte : le **paquet** d'abord, puis les ressources téléchargées — et seulement si
    /// leurs images y sont réellement. Se fier à l'existence d'une ressource distante ne suffisait
    /// pas : pendant le téléchargement, le dossier existe sans images, et l'application ouvrait
    /// alors un dossier vide au lieu du mushaf embarqué.
    static func readingDirectory(_ reading: Reading, container: AppDependencies) -> URL? {
        if let bundlePath = Bundle.main.url(forResource: reading.localPath, withExtension: nil) {
            logger.info("Images: Use bundle for reading \(reading)")
            return bundlePath
        }

        let remotePath = container.remoteResources?.resource(for: reading)?.downloadDestination.url
        guard let remotePath, reading.hasImages(at: remotePath) else {
            logger.error("Images: No images for reading \(reading); neither bundled nor downloaded")
            return nil
        }
        logger.info("Images: Use downloaded for reading \(reading)")
        return remotePath
    }

    // MARK: Private

    private let container: AppDependencies
    private let overlayService: VerseOverlayService
}

private extension Reading {
    // TODO: Add cropInsets back
    var cropInsets: UIEdgeInsets {
        switch self {
        case .hafs_1405:
            return .zero // UIEdgeInsets(top: 10, left: 34, bottom: 40, right: 24)
        case .hafs_1421:
            return .zero
        case .hafs_1440:
            return .zero
        case .hafs_1439:
            return .zero
        case .hafs_1441:
            return .zero
        case .tajweed:
            return .zero
        case .indoPak:
            return .zero
        }
    }
}
