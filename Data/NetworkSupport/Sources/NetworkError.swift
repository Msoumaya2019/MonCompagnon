//
//  NetworkError.swift
//  SwinjectMVVMExample
//
//  Created by Yoichi Tagaya on 8/22/15.
//  Copyright © 2015 Swinject Contributors. All rights reserved.
//

import Foundation
import Localization

public enum NetworkError: Error {
    /// Unknown or not supported error.
    case unknown(Error?)

    /// Not connected to the internet.
    case notConnectedToInternet

    /// International data roaming turned off.
    case internationalRoamingOff

    /// Connection is lost.
    case connectionLost

    /// Cannot reach the server.
    case serverNotReachable

    case serverError(String)

    // MARK: Lifecycle

    public init(error: Error) {
        if let error = error as? NetworkError {
            self = error
        } else if let error = error as? URLError {
            switch error.code {
            case .timedOut, .cannotFindHost, .cannotConnectToHost:
                self = .serverNotReachable
            case .networkConnectionLost:
                self = .connectionLost
            case .dnsLookupFailed:
                self = .serverNotReachable
            case .notConnectedToInternet:
                self = .notConnectedToInternet
            case .internationalRoamingOff:
                self = .internationalRoamingOff
            default:
                self = .unknown(error)
            }
        } else {
            self = .unknown(error)
        }
    }
}

extension NetworkError: LocalizedError {
    /// Le message à montrer, avec de quoi savoir **ce qui** a échoué.
    ///
    /// Le message générique est le point de sortie de trop d'erreurs différentes pour dire quoi
    /// que ce soit : un domaine réseau non reconnu, un code de statut inattendu et une base
    /// illisible s'y rendent à l'identique. On y accole donc l'identité de l'erreur d'origine —
    /// son domaine et son code — et le détail quand il y en a un. Sans cela, aucune capture
    /// d'écran ne permet de diagnostiquer l'échec, et il faut reconstruire l'application pour
    /// l'apprendre : c'est exactement ce qui est arrivé aux téléchargements de récitateurs.
    public var errorDescription: String? {
        switch self {
        case .unknown(let underlying):
            return "\(l("error.message.general")) (\(Self.identify(underlying)))"
        case .serverError(let detail):
            return "\(l("error.message.general")) (\(detail))"
        case .serverNotReachable:
            return l("error.message.general")
        case .notConnectedToInternet:
            return l("error.message.not_connected_to_internet")
        case .internationalRoamingOff:
            return l("error.message.international_roaming_off")
        case .connectionLost:
            return l("error.message.connection_lost")
        }
    }

    /// « NSURLErrorDomain -1009 », ou « aucun » si l'erreur d'origine manque.
    private static func identify(_ error: Error?) -> String {
        guard let error else {
            return "aucune erreur d'origine"
        }
        let nsError = error as NSError
        return "\(nsError.domain) \(nsError.code)"
    }
}
