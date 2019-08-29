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

import class Foundation.ProcessInfo
import Logging

/// Settings used to configure an `ActorSystem`.
public struct ActorSystemSettings {
    public static var `default`: ActorSystemSettings {
        return .init()
    }

    // TODO: LoggingSettings

    /// Configure default log level for all `Logger` instances created by the library.
    public var defaultLogLevel: Logger.Level = .info // TODO: maybe remove this? should be up to logging library to configure for us as well

    /// Optionally override Logger that shall be offered to actors and the system.
    /// This is used instead of globally configured `Logging.Logger()` factories by the actor system.
    public var overrideLogger: Logger?

    // TODO: hope to remove this once a StdOutLogHandler lands that has formatting support;
    // logs are hard to follow with not consistent order of metadata etc (like system address etc).
    public var useBuiltInFormatter: Bool = true

    public var actor: ActorSettings = .default
    public var serialization: SerializationSettings = .default
    public var metrics: MetricsSettings = .default(rootName: nil)
    public var cluster: ClusterSettings = .default {
        didSet {
            self.serialization.localNode = self.cluster.uniqueBindNode
        }
    }

    // FIXME: should have more proper config section
    public var threadPoolSize: Int = ProcessInfo.processInfo.activeProcessorCount
}

public struct ActorSettings {
    public static var `default`: ActorSettings {
        return .init()
    }

    // arbitrarily selected, we protect start() using it; we may lift this restriction if needed
    public var maxBehaviorNestingDepth: Int = 128
}
