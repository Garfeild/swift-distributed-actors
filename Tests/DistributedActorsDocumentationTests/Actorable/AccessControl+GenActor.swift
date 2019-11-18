// ==== ------------------------------------------------------------------ ====
// === DO NOT EDIT: Generated by GenActors                     
// ==== ------------------------------------------------------------------ ====

//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2018-2019 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.md for the list of Swift Distributed Actors project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

// tag::imports[]

import DistributedActors

// end::imports[]

import DistributedActorsTestKit
import XCTest
// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: DO NOT EDIT: Generated AccessControl messages 

/// DO NOT EDIT: Generated AccessControl messages
extension AccessControl {
    // TODO: make Message: Codable - https://github.com/apple/swift-distributed-actors/issues/262
    public enum Message { 
        case greetPublicly 
        case greetInternal 
    }

    
}
// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: DO NOT EDIT: Generated AccessControl behavior

extension AccessControl {

    public static func makeBehavior(instance: AccessControl) -> Behavior<Message> {
        return .setup { _context in
            let context = Actor<AccessControl>.Context(underlying: _context)
            let instance = instance

            /* await */ instance.preStart(context: context)

            return Behavior<Message>.receiveMessage { message in
                switch message { 
                
                case .greetPublicly:
                    instance.greetPublicly()
 
                case .greetInternal:
                    instance.greetInternal()
 
                
                }
                return .same
            }.receiveSignal { _context, signal in 
                let context = Actor<AccessControl>.Context(underlying: _context)

                switch signal {
                case is Signals.PostStop: 
                    instance.postStop(context: context)
                    return .same
                case let terminated as Signals.Terminated:
                    switch instance.receiveTerminated(context: context, terminated: terminated) {
                    case .unhandled: 
                        return .unhandled
                    case .stop: 
                        return .stop
                    case .ignore: 
                        return .same
                    }
                default:
                    return .unhandled
                }
            }
        }
    }
}
// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: Extend Actor for AccessControl

extension Actor where A.Message == AccessControl.Message {
    
    public func greetPublicly() {
    self.ref.tell(.greetPublicly)
} 
    
    internal func greetInternal() {
    self.ref.tell(.greetInternal)
} 
    
}
