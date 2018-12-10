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

import NIOConcurrencyHelpers
import Dispatch
import CDungeon

/// An `ActorSystem` is a confined space which runs and manages Actors.
///
/// Most applications need _no-more-than_ a single `ActorSystem`.
/// Rather, the system should be configured to host the kinds of dispatchers that the application needs.
///
/// An `ActorSystem` and all of the actors contained within remain alive until the `terminate` call is made.
public final class ActorSystem {
    // TODO: think about if we need ActorSystem to IS-A ActorRef; in Typed we did so, but it complicated the understanding of it to users...
    // it has upsides though, it is then possible to expose additional async APIs on it, without doing any weird things
    // creating an actor them becomes much simpler; it becomes an `ask` and we can avoid locks then (!)

    public let name: String

    // Implementation note:
    // First thing we need to start is the event stream, since is is what powers our logging infrastructure // TODO: ;-)
    // so without it we could not log anything.
    let eventStream = "" // FIXME actual implementation

    @usableFromInline let deadLetters: ActorRef<DeadLetter>

    /// Impl note: Atomic since we are being called from outside actors here (or MAY be), thus we need to synchronize access
    private let anonymousNames = AtomicAnonymousNamesGenerator(prefix: "$") // TODO: make the $ a constant TODO: where

    private let dispatcher: MessageDispatcher

    // Note: This differs from Akka, we do full separate trees here
    private let systemProvider: ActorRefProvider // TODO maybe we don't need this?
    private let userProvider: ActorRefProvider // TODO maybe we don't need this?

    private let _theOneWhoWalksTheBubblesOfSpaceTime: ReceivesSystemMessages

    private let terminationLock = Lock()

//  // TODO: provider is what abstracts being able to fabricate remote or local actor refs
//  // Implementation note:
//  // We MAY be able to get rid of this (!), I think in Akka it causes some indirections which we may not really need... we'll see
//  private let provider =

    // FIXME should link to the logging infra rather than be ad hoc (init will be tricky, chicken-and-egg ;-))
    // TODO: lazy var is unsafe here
    public lazy var log: ActorLogger = ActorLogger(self)
    // the tricky stuff is due to
    // /Users/ktoso/code/sact/Sources/Swift Distributed ActorsActor/ActorSystem.swift:55:16: error: 'self' used before all stored properties are initialized
    // self.log = ActorLogger(self)

    /// Creates a named ActorSystem; The name is useful for debugging cross system communication
    // TODO: /// - throws: when configuration requirements can not be fulfilled (e.g. use of OS specific dispatchers is requested on not-matching OS)
    public init(_ name: String) {
        self.name = name

        self._theOneWhoWalksTheBubblesOfSpaceTime = TheOneWhoHasNoParentActorRef()
        let theOne = self._theOneWhoWalksTheBubblesOfSpaceTime
        let userGuardian = Guardian(parent: theOne, name: "user")
        let systemGuardian = Guardian(parent: theOne, name: "system")

        self.userProvider = LocalActorRefProvider(root: userGuardian)
        self.systemProvider = LocalActorRefProvider(root: systemGuardian)

        // dead letters init
        // TODO actually attach dead letters to a parent?
        let deadLettersPath = try! ActorPath(root: "system") / ActorPathSegment("deadLetters") // TODO actually make child of system
        let deadLog = LoggerFactory.make(identifier: deadLettersPath.description)
        self.deadLetters = DeadLettersActorRef(deadLog, path: deadLettersPath.makeUnique(uid: .opaque))

        self.dispatcher = try! FixedThreadPool(4) // TODO: better guesstimate on start and also make it tuneable

        do {
            try FaultHandling.installCrashHandling()
        } catch {
            CDungeon.sact_dump_backtrace()
            fatalError("Unable to install crash handling signal handler. Terminating. Error was: \(error)")
        }
    }

    public convenience init() {
        self.init("ActorSystem")
    }

    // FIXME we don't do any hierarchy right now

    // TODO: should we depend on NIO already? I guess so hm they have the TimeAmount... Tho would be nice to split it out maybe
    public func terminate(/* TimeAmount */) -> Awaitable {
        // TODO: cause termination here
        return whenTerminated()
    }

    /// - Warning: Blocks current thread until the system has terminated.
    ///            Do not call from within actors or you may deadlock shutting down the system.
    public func whenTerminated() -> Awaitable {
        // return Awaitable(underlyingLock: terminationLock)
        return undefined() // FIXME: implement this
    }
}

/// Public but not intended for user-extension.
///
/// An `ActorRefFactory` is able to create ("spawn") new actors and return `ActorRef` instances for them.
/// Only the `ActorSystem`, `ActorContext` and potentially testing facilities can ever expose this ability.
public protocol ActorRefFactory {

    /// Spawn an actor with the given behavior name and props.
    ///
    /// Returns: `ActorRef` for the spawned actor.
    func spawn<Message>(_ behavior: Behavior<Message>, name: String, props: Props) throws -> ActorRef<Message>
}

// MARK: Actor creation

extension ActorSystem: ActorRefFactory {

    /// Spawn a new top-level Actor with the given initial behavior and name.
    ///
    /// - throws: when the passed behavior is not a legal initial behavior
    /// - throws: when the passed actor name contains illegal characters (e.g. symbols other than "-" or "_")
    public func spawn<Message>(_ behavior: Behavior<Message>, name: String, props: Props = Props()) throws -> ActorRef<Message> {
        guard !name.starts(with: "$") else {
            // only system and anonymous actors are allowed have names beginning with "$"
            throw ActorPathError.illegalLeadingSpecialCharacter(name: name, illegal: "$")
        }

        return try self.spawnInternal(behavior, name: name, props: props)
    }

    // Actual spawn implementation, minus the leading "$" check on names;
    // spawnInternal is used by spawnAnonymous and others, which are privileged and may start with "$"
    private func spawnInternal<Message>(_ behavior: Behavior<Message>, name: String, props: Props = Props()) throws -> ActorRef<Message> {
        try behavior.validateAsInitial() // TODO: good example of what would be a soft crash...

        let path = try self.userProvider.rootPath.makeChildPath(name: name, uid: .random())
        // TODO: reserve the name, atomically

        let refWithCell: ActorRef<Message> = userProvider.spawn(
            system: self,
            behavior: behavior, path: path,
            dispatcher: dispatcher, props: props
        )

        return refWithCell
    }

    // TODO _systemSpawn: for spawning under the system one

    public func spawn<Message>(_ behavior: ActorBehavior<Message>, name: String, props: Props = Props()) throws -> ActorRef<Message> {
        return try spawn(.custom(behavior: behavior), name: name, props: props)
    }

    // Implementation note:
    // It is important to have the anonymous one have a "long discouraging name", we want actors to be well named,
    // and developers should only opt into anonymous ones when they are aware that they do so and indeed that's what they want.
    // This is why there should not be default parameter values for actor names
    public func spawnAnonymous<Message>(_ behavior: Behavior<Message>, props: Props = Props()) throws -> ActorRef<Message> {
        return try spawnInternal(behavior, name: self.anonymousNames.nextName(), props: props)
    }

    public func spawnAnonymous<Message>(_ behavior: ActorBehavior<Message>, props: Props = Props()) throws -> ActorRef<Message> {
        return try spawnAnonymous(.custom(behavior: behavior), props: props)
    }
}
