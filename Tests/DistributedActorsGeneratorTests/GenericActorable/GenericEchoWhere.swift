////===----------------------------------------------------------------------===//
////
//// This source file is part of the Swift Distributed Actors open source project
////
//// Copyright (c) 2019-2020 Apple Inc. and the Swift Distributed Actors project authors
//// Licensed under Apache License v2.0
////
//// See LICENSE.txt for license information
//// See CONTRIBUTORS.md for the list of Swift Distributed Actors project authors
////
//// SPDX-License-Identifier: Apache-2.0
////
////===----------------------------------------------------------------------===//
//
//import DistributedActors
//import _Distributed
//
//distributed actor GenericEchoWhere<One, Two: Codable>
//    where One: Codable, One: Hashable {
//
//    distributed func echoOne(_ one: One) -> One {
//        one
//    }
//
//    distributed func echoTwo(_ two: Two) -> Two {
//        two
//    }
//}
