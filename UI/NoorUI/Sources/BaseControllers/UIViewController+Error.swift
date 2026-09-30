//
//  UIViewController+Error.swift
//  Quran
//
//  Created by Mohamed Afifi on 2/27/17.
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
import Localization
import UIKit

extension UIViewController {
    public func showErrorAlert(error: Error) {
        if error.isCancelled {
            return
        }
        if Thread.current.isMainThread {
            _showErrorAlert(error: error)
        } else {
            DispatchQueue.main.async {
                self._showErrorAlert(error: error)
            }
        }
    }

    private func _showErrorAlert(error: Error) {
        crasher.recordError(error, reason: "showErrorAlert")
        let message = error.getErrorDescription()
        let controller = UIAlertController(title: l("error.dialog.title"), message: message, preferredStyle: .alert)
        controller.addAction(UIAlertAction(title: "Ok", style: .cancel, handler: nil))
        present(controller, animated: true)
    }
}

extension Error {
    /// Le message à montrer à l'utilisateur.
    ///
    /// Point de passage unique des alertes de l'application : le modificateur SwiftUI
    /// `errorAlert` et `showErrorAlert` s'y ramènent tous les deux. Une erreur qui n'est pas
    /// `LocalizedError` — une erreur POSIX, un `NSError` rendu par le système — n'a aucune
    /// description, et tombait donc sur le message générique : muet. On y accole son domaine et
    /// son code, pour qu'une capture d'écran suffise à savoir ce qui a échoué.
    func getErrorDescription() -> String {
        let generic = l("error.message.general")
        if let description = (self as? LocalizedError)?.errorDescription, description != generic {
            return description
        }
        let nsError = self as NSError
        return "\(generic) (\(nsError.domain) \(nsError.code))"
    }
}
