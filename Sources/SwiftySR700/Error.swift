//
//  Error.swift
//  
//
//  Created by James Balnaves on 3/30/20.
//

import Foundation

enum RoasterError: Error {
    case valueError
    case lookupError(String)
    case stateError
}
