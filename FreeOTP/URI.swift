//
//  URI.swift
//  FreeOTP
//
//  Created by Justin Stephenson on 2/5/20.
//  Copyright © 2020 Fedora Project. All rights reserved.
//

import Foundation

class URI {
    struct Params {
        var issuer = ""
        var account = ""
        var label = ""
        var lock = ""
        var image = ""
        var algorithm = ""
        var period = ""
        var digits = ""
        var counter = ""

        mutating func updateProperty(name: String, value: String) {
            switch name {
            case "lock": self.lock = value
            case "image": self.image = value
            case "algorithm": self.algorithm = value
            case "period": self.period = value
            case "digits": self.digits = value
            case "counter": self.counter = value

            default:
                return
            }
        }
    }

    let queryItems = ["lock", "image", "algorithm", "period", "digits", "counter"]
    let algorithms = ["SHA1", "SHA224", "SHA256", "SHA384", "SHA512"]
    let period = ["15", "30", "60", "120", "300", "600"]
    let digits = ["6", "8"]

    func setQueryItems(_ params: inout Params, _ urlc: URLComponents) -> Params! {
        let mirror = Mirror(reflecting: params)

        for child in mirror.children  {
            if let itemValue = (urlc.queryItems?.first(where: { $0.name == child.label})) {
                if let itemName = child.label {
                    params.updateProperty(name: itemName, value: itemValue.value!)
                }
            }
        }

        return params
    }

    // Explode a URLComponent string into a Params structure
    func parseUrlc(_ urlc: URLComponents) -> Params! {
        var params = Params()

        var path = urlc.path
        while path.hasPrefix("/") {
            path = String(path[path.index(path.startIndex, offsetBy: 1)...])
        }
        if path == "" {
            return nil
        }

        let components = path.components(separatedBy: ":")

        if components.count == 1 {
            params.account = components[0]
        } else {
            params.issuer = components[0]
        }
        params.label = components.count > 1 ? components[1] : ""

        params = setQueryItems(&params, urlc)

        return params
    }
}
