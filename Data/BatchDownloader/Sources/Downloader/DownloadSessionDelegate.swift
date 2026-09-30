//
//  DownloadSessionDelegate.swift
//  Quran
//
//  Created by Mohamed Afifi on 5/14/16.
//
//  Quran for iOS is a Quran reading application for iOS.
//  Copyright (C) 2017  Quran.com
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//

import Crashing
import Foundation
import NetworkSupport
import SystemDependencies
import Utilities
import VLogging

actor DownloadSessionDelegate: NetworkSessionDelegate {
    // MARK: Lifecycle

    init(dataController: DownloadBatchDataController, fileManager: FileSystem) {
        self.dataController = dataController
        self.fileManager = fileManager
    }

    // MARK: Internal

    @MainActor var backgroundSessionCompletion: (@MainActor () -> Void)?

    @MainActor
    func setBackgroundSessionCompletion(_ backgroundSessionCompletion: @MainActor @escaping () -> Void) {
        self.backgroundSessionCompletion = backgroundSessionCompletion
    }

    func networkSession(
        _ session: NetworkSession,
        downloadTask: NetworkSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) async {
        guard let response = await dataController.downloadRequestResponse(for: downloadTask) else {
            logger.warning("[networkSession:didWriteData] Cannot find onGoingDownloads for task \(describe(downloadTask))")
            return
        }
        let progress = DownloadProgress(total: Double(totalBytesExpectedToWrite), completed: Double(totalBytesWritten))
        await response.response.updateProgress(of: response.request, progress)
    }

    func networkSession(_ session: NetworkSession, downloadTask: NetworkSessionDownloadTask, didFinishDownloadingTo location: URL) async {
        // validate task response
        guard validate(task: downloadTask) == nil else {
            logger.error("Invalid server response \(downloadTask.taskIdentifier) - \(String(describing: downloadTask.response))")
            return
        }

        guard let response = await dataController.downloadRequestResponse(for: downloadTask) else {
            logger.warning("Missed saving task \(describe(downloadTask))")
            return
        }

        let resumePath = response.request.resumePath
        let destinationURL = response.request.destination

        // remove the resume data
        try? fileManager.removeItem(at: resumePath)
        // remove the existing file if exist.
        try? fileManager.removeItem(at: destinationURL)

        // create directory if needed
        let directory = destinationURL.deletingLastPathComponent()
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        // Downloaded resources can be fetched again, including files extracted here later.
        do {
            try fileManager.setExcludedFromBackup(true, at: directory)
        } catch {
            crasher.recordError(error, reason: "Couldn't exclude download directory from backup '\(directory)'")
        }

        // move the file to destination
        do {
            try fileManager.moveItem(at: location, to: destinationURL)

        } catch {
            crasher.recordError(
                error,
                reason: "Problem with creating directory or copying item to the new location '\(destinationURL)'"
            )
            // fail the batch since we save the file
            await dataController.downloadFailed(response, with: FileSystemError(error: error))
        }
    }

    func networkSession(_ session: NetworkSession, task: NetworkSessionTask, didCompleteWithError sessionError: Error?) async {
        logger.debug("Finished downloading \(describe(task)). Error: \(String(describing: sessionError))")
        guard let response = await dataController.downloadRequestResponse(for: task) else {
            if let sessionError, !sessionError.isCancelled {
                logger.warning("[networkSession:didCompleteWithError] Cannot find onGoingDownloads for task \(describe(task))")
            }
            return
        }

        let validationError = validate(task: task)
        let theError = sessionError ?? validationError

        // if success, early return
        guard let error = theError else {
            await dataController.downloadCompleted(response)
            return
        }

        let finalError = wrap(error: error, resumePath: response.request.resumePath)
        await dataController.downloadFailed(response, with: finalError)
    }

    @MainActor
    func networkSessionDidFinishEvents(forBackgroundURLSession session: NetworkSession) {
        backgroundSessionCompletion?()
        backgroundSessionCompletion = nil
    }

    // MARK: Private

    private let acceptableStatusCodes = 200 ..< 300

    private let dataController: DownloadBatchDataController
    private let fileManager: FileSystem

    private func wrap(error theError: Error, resumePath: RelativeFilePath) -> Error {
        var error = theError

        // save resume data, if found
        if let resumeData = error.resumeData {
            do {
                try resumeData.write(to: resumePath, options: [.atomic])
            } catch {
                crasher.recordError(error, reason: "Error while saving resume data.")
            }
            error = error.removeResumeData()
        }

        // not cancelled by user
        guard !error.isCancelled else {
            return error
        }

        crasher.recordError(error, reason: "Download network error occurred")

        // `-3000` — « Impossible de créer le fichier » — dit qu'écrire a échoué, sans dire
        // pourquoi. On ne peut donc pas en conclure que le disque est plein : c'est l'espace encore
        // libre, mesuré ici, qui tranche. Il va au journal et non dans l'alerte, car une alerte qui
        // affiche un nombre de gigaoctets se lit comme une taille de téléchargement — ce qui a
        // envoyé la recherche du côté du disque, alors qu'il restait 17 Go.
        if Self.cannotCreateFile(error) {
            logger.error("Cannot create the downloaded file. Free space: \(availableDiskSpaceDescription())")
        }

        let finalError: Error = if Self.isOutOfSpace(error) {
            FileSystemError.noDiskSpace
        } else {
            NetworkError(error: error)
        }
        return finalError
    }

    /// Un disque plein, dit par le système lui-même : `ENOSPC`, « no space left on device ».
    ///
    /// Le code testé ici était auparavant `ENOENT`, qui veut dire « fichier introuvable », sous un
    /// commentaire parlant de disque plein : il ne pouvait donc jamais être vrai pour la bonne
    /// raison, et le message qui annonce la panne restait hors d'atteinte.
    private static func isOutOfSpace(_ error: Error) -> Bool {
        (error as? POSIXError)?.code == .ENOSPC
    }

    /// `NSURLErrorCannotCreateFile`, code `-3000` : iOS a reçu les octets mais n'a pas pu créer le
    /// fichier. Un disque plein en est une cause possible, pas la seule — et pas celle-ci.
    private static func cannotCreateFile(_ error: Error) -> Bool {
        (error as? URLError)?.code == .cannotCreateFile
    }

    /// L'espace encore disponible pour l'application, en octets, ou `nil` s'il est illisible.
    private func availableDiskSpace() -> Int64? {
        let values = try? fileManager.resourceValues(
            at: FileManager.documentsURL,
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        )
        return values?.availableCapacity
    }

    /// Le même chiffre, en clair, pour le journal.
    private func availableDiskSpaceDescription() -> String {
        guard let availableBytes = availableDiskSpace() else {
            return "unknown"
        }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: availableBytes)
    }

    private func validate(task: NetworkSessionTask) -> Error? {
        let httpResponse = task.response as? HTTPURLResponse
        let statusCode = httpResponse?.statusCode ?? 0
        if !acceptableStatusCodes.contains(statusCode) {
            return NetworkError.serverError("Unacceptable status code: \(statusCode)")
        } else {
            return nil
        }
    }
}

private extension Error {
    var resumeData: Data? {
        (self as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data
    }

    func removeResumeData() -> Error {
        let error = self as NSError
        guard error.userInfo[NSURLSessionDownloadTaskResumeData] != nil else {
            return self
        }
        var userInfo = error.userInfo
        userInfo[NSURLSessionDownloadTaskResumeData] = nil
        return NSError(domain: error.domain, code: error.code, userInfo: userInfo)
    }
}
