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

import NIO
import Dispatch

protocol ChildActorRefFactory: ActorRefFactory {
    // MARK: Interface with actor cell

    var children: Children { get set }

    // MARK: Additional

    func spawn<Message>(_ behavior: Behavior<Message>, name: String, props: Props) throws -> ActorRef<Message>
    func stop<M>(child ref: ActorRef<M>) throws

}

/// Represents all the (current) children this actor has spawned.
///
/// Convenience methods for locating children are provided, although it is recommended to keep the `ActorRef`
/// of spawned actors in the context of where they are used, rather than looking them up continuously.
public struct Children {

    // Implementation note: access is optimized for fetching by name, as that's what we do during child lookup
    // as well as actor tree traversal.
    typealias Name = String
    private var container: [Name: BoxedHashableAnyReceivesSystemMessages]

    public init() {
        self.container = [:]
    }

    public func hasChild(identifiedBy uniquePath: UniqueActorPath) -> Bool {
        guard let child = self.container[uniquePath.name] else { return false }
        return child.path == uniquePath
    }
    
    // TODO (ktoso): Don't like the withType name... better ideas for this API?
    public func find<T>(named name: String, withType type: T.Type) -> ActorRef<T>? {
        guard let boxedChild = container[name] else {
            return nil
        }

        return boxedChild.internal_exposeAs(ActorRef<T>.self)
    }
    
    public mutating func insert<T, R: ActorRef<T>>(_ childRef: R) {
        self.container[childRef.path.name] = childRef.internal_boxAnyReceivesSystemMessages()
    }

    /// Imprecise contains function, which only checks for the existence of a child actor by its name,
    /// without taking into account its incarnation UID.
    ///
    /// - SeeAlso: `contains(identifiedBy:)`
    internal func contains(name: String) -> Bool {
        return container.keys.contains(name)
    }
    /// Precise contains function, which checks if this children container contains the specific actor
    /// identified by the passed in path.
    ///
    /// - SeeAlso: `contains(_:)`
    internal func contains(identifiedBy uniquePath: UniqueActorPath) -> Bool {
        guard let boxedChild: BoxedHashableAnyReceivesSystemMessages = self.container[uniquePath.name] else {
            return false
        }

        return boxedChild.path == uniquePath
    }

    /// INTERNAL API: Only the ActorCell may mutate its children collection (as a result of spawning or stopping them).
    /// Returns: `true` upon successful removal and the the passed in ref was indeed a child of this actor, `false` otherwise
    @usableFromInline
    internal mutating func removeChild(identifiedBy path: UniqueActorPath) -> Bool {
        if let ref = container[path.name] {
            if ref.path.uid == path.uid {
                return container.removeValue(forKey: path.name) != nil
            } // else we either tried to remove a child twice, or it was not our child so nothing to remove
        }

        return false
    }

}

// TODO: Trying this style rather than the style done with DeathWatch to extend cell's capabilities
extension ActorCell: ChildActorRefFactory {

    // TODO: Very similar to top level one, though it will be differing in small bits... Likely not worth to DRY completely
    internal func internal_spawn<M>(_ behavior: Behavior<M>, name: String, props: Props) throws -> ActorRef<M> {
        try behavior.validateAsInitial()
        try validateUniqueName(name)
        // TODO prefix $ validation (only ok for anonymous)

        let path = try self.path.makeChildPath(name: name, uid: .random())

        // TODO reserve name

        let d = dispatcher // TODO this is dispatcher inheritance, we dont want that I think
        let cell: ActorCell<M> = ActorCell<M>(
            system: self.system,
            parent: self.myself.internal_boxAnyReceivesSystemMessages(),
            behavior: behavior,
            path: path,
            props: props,
            dispatcher: d
        )
        let mailbox = Mailbox(cell: cell, capacity: props.mailbox.capacity)

        log.info("Spawning [\(behavior)], on path: [\(path)]")

        let refWithCell = ActorRefWithCell(
            path: path,
            cell: cell,
            mailbox: mailbox
        )

        self.children.insert(refWithCell)

        cell.set(ref: refWithCell)
        refWithCell.sendSystemMessage(.start)

        return refWithCell
    }

    internal func internal_stop<T>(child ref: ActorRef<T>) throws {
        // we immediately attempt the remove since
        guard ref.path.isChildPathOf(self.path) else {
            throw ActorContextError.attemptedStoppingNonChildActor(ref: ref)
        }

        if self.children.removeChild(identifiedBy: ref.path) {
            ref.internal_downcast.sendSystemMessage(.stop)
        }
    }

    private func validateUniqueName(_ name: String) throws {
        if children.contains(name: name) {
            let childPath: ActorPath = try self.path.makeChildPath(name: name)
            throw ActorContextError.duplicateActorPath(path: childPath)
        }
    }
}

/// Errors which can occur while executing actions on the [ActorContext].
public enum ActorContextError: Error {
    case attemptedStoppingNonChildActor(ref: AnyAddressableActorRef)
    case duplicateActorPath(path: ActorPath)
}
