//
//  Publishers.Merge.swift
//  Combine (ported from OpenCombine)
//
//  AppKitCross addition: OpenCombine 0.14.0 lists Merge/MergeMany in its remaining
//  interface and does not implement them. The declarations below are Apple's; the
//  implementation is shared by all arities through `MergeInner`, which subscribes to the
//  type-erased upstreams, interleaves their values, buffers while downstream demand is
//  zero, finishes once every upstream has finished and fails on the first failure.

// swiftlint:disable file_length large_tuple

extension Publishers {

    /// A publisher created by applying the merge function to two upstream publishers.
    public struct Merge<A: Publisher, B: Publisher>: Publisher
        where A.Failure == B.Failure, A.Output == B.Output
    {
        public typealias Output = A.Output

        public typealias Failure = A.Failure

        public let a: A

        public let b: B

        public init(_ a: A, _ b: B) {
            self.a = a
            self.b = b
        }

        public func receive<Downstream: Subscriber>(subscriber: Downstream)
            where B.Failure == Downstream.Failure, B.Output == Downstream.Input
        {
            MergeInner(downstream: subscriber,
                       upstreams: [a.eraseToAnyPublisher(), b.eraseToAnyPublisher()])
                .start()
        }

        public func merge<P: Publisher>(with other: P) -> Publishers.Merge3<A, B, P>
            where B.Failure == P.Failure, B.Output == P.Output
        {
            return .init(a, b, other)
        }

        public func merge<Z: Publisher, Y: Publisher>(with z: Z, _ y: Y)
            -> Publishers.Merge4<A, B, Z, Y>
            where B.Failure == Z.Failure, B.Output == Z.Output,
                  Z.Failure == Y.Failure, Z.Output == Y.Output
        {
            return .init(a, b, z, y)
        }

        public func merge<Z: Publisher, Y: Publisher, X: Publisher>(with z: Z, _ y: Y, _ x: X)
            -> Publishers.Merge5<A, B, Z, Y, X>
            where B.Failure == Z.Failure, B.Output == Z.Output,
                  Z.Failure == Y.Failure, Z.Output == Y.Output,
                  Y.Failure == X.Failure, Y.Output == X.Output
        {
            return .init(a, b, z, y, x)
        }

        public func merge<Z: Publisher, Y: Publisher, X: Publisher, W: Publisher>(
            with z: Z, _ y: Y, _ x: X, _ w: W
        ) -> Publishers.Merge6<A, B, Z, Y, X, W>
            where B.Failure == Z.Failure, B.Output == Z.Output,
                  Z.Failure == Y.Failure, Z.Output == Y.Output,
                  Y.Failure == X.Failure, Y.Output == X.Output,
                  X.Failure == W.Failure, X.Output == W.Output
        {
            return .init(a, b, z, y, x, w)
        }

        public func merge<Z: Publisher, Y: Publisher, X: Publisher, W: Publisher, V: Publisher>(
            with z: Z, _ y: Y, _ x: X, _ w: W, _ v: V
        ) -> Publishers.Merge7<A, B, Z, Y, X, W, V>
            where B.Failure == Z.Failure, B.Output == Z.Output,
                  Z.Failure == Y.Failure, Z.Output == Y.Output,
                  Y.Failure == X.Failure, Y.Output == X.Output,
                  X.Failure == W.Failure, X.Output == W.Output,
                  W.Failure == V.Failure, W.Output == V.Output
        {
            return .init(a, b, z, y, x, w, v)
        }

        public func merge<Z: Publisher, Y: Publisher, X: Publisher, W: Publisher,
                          V: Publisher, U: Publisher>(
            with z: Z, _ y: Y, _ x: X, _ w: W, _ v: V, _ u: U
        ) -> Publishers.Merge8<A, B, Z, Y, X, W, V, U>
            where B.Failure == Z.Failure, B.Output == Z.Output,
                  Z.Failure == Y.Failure, Z.Output == Y.Output,
                  Y.Failure == X.Failure, Y.Output == X.Output,
                  X.Failure == W.Failure, X.Output == W.Output,
                  W.Failure == V.Failure, W.Output == V.Output,
                  V.Failure == U.Failure, V.Output == U.Output
        {
            return .init(a, b, z, y, x, w, v, u)
        }
    }

    /// A publisher created by applying the merge function to three upstream publishers.
    public struct Merge3<A: Publisher, B: Publisher, C: Publisher>: Publisher
        where A.Failure == B.Failure, A.Output == B.Output,
              B.Failure == C.Failure, B.Output == C.Output
    {
        public typealias Output = A.Output

        public typealias Failure = A.Failure

        public let a: A

        public let b: B

        public let c: C

        public init(_ a: A, _ b: B, _ c: C) {
            self.a = a
            self.b = b
            self.c = c
        }

        public func receive<Downstream: Subscriber>(subscriber: Downstream)
            where C.Failure == Downstream.Failure, C.Output == Downstream.Input
        {
            MergeInner(downstream: subscriber,
                       upstreams: [a.eraseToAnyPublisher(),
                                   b.eraseToAnyPublisher(),
                                   c.eraseToAnyPublisher()])
                .start()
        }

        public func merge<P: Publisher>(with other: P) -> Publishers.Merge4<A, B, C, P>
            where C.Failure == P.Failure, C.Output == P.Output
        {
            return .init(a, b, c, other)
        }

        public func merge<Z: Publisher, Y: Publisher>(with z: Z, _ y: Y)
            -> Publishers.Merge5<A, B, C, Z, Y>
            where C.Failure == Z.Failure, C.Output == Z.Output,
                  Z.Failure == Y.Failure, Z.Output == Y.Output
        {
            return .init(a, b, c, z, y)
        }

        public func merge<Z: Publisher, Y: Publisher, X: Publisher>(with z: Z, _ y: Y, _ x: X)
            -> Publishers.Merge6<A, B, C, Z, Y, X>
            where C.Failure == Z.Failure, C.Output == Z.Output,
                  Z.Failure == Y.Failure, Z.Output == Y.Output,
                  Y.Failure == X.Failure, Y.Output == X.Output
        {
            return .init(a, b, c, z, y, x)
        }

        public func merge<Z: Publisher, Y: Publisher, X: Publisher, W: Publisher>(
            with z: Z, _ y: Y, _ x: X, _ w: W
        ) -> Publishers.Merge7<A, B, C, Z, Y, X, W>
            where C.Failure == Z.Failure, C.Output == Z.Output,
                  Z.Failure == Y.Failure, Z.Output == Y.Output,
                  Y.Failure == X.Failure, Y.Output == X.Output,
                  X.Failure == W.Failure, X.Output == W.Output
        {
            return .init(a, b, c, z, y, x, w)
        }

        public func merge<Z: Publisher, Y: Publisher, X: Publisher, W: Publisher, V: Publisher>(
            with z: Z, _ y: Y, _ x: X, _ w: W, _ v: V
        ) -> Publishers.Merge8<A, B, C, Z, Y, X, W, V>
            where C.Failure == Z.Failure, C.Output == Z.Output,
                  Z.Failure == Y.Failure, Z.Output == Y.Output,
                  Y.Failure == X.Failure, Y.Output == X.Output,
                  X.Failure == W.Failure, X.Output == W.Output,
                  W.Failure == V.Failure, W.Output == V.Output
        {
            return .init(a, b, c, z, y, x, w, v)
        }
    }

    /// A publisher created by applying the merge function to four upstream publishers.
    public struct Merge4<A: Publisher, B: Publisher, C: Publisher, D: Publisher>: Publisher
        where A.Failure == B.Failure, A.Output == B.Output,
              B.Failure == C.Failure, B.Output == C.Output,
              C.Failure == D.Failure, C.Output == D.Output
    {
        public typealias Output = A.Output

        public typealias Failure = A.Failure

        public let a: A

        public let b: B

        public let c: C

        public let d: D

        public init(_ a: A, _ b: B, _ c: C, _ d: D) {
            self.a = a
            self.b = b
            self.c = c
            self.d = d
        }

        public func receive<Downstream: Subscriber>(subscriber: Downstream)
            where D.Failure == Downstream.Failure, D.Output == Downstream.Input
        {
            MergeInner(downstream: subscriber,
                       upstreams: [a.eraseToAnyPublisher(),
                                   b.eraseToAnyPublisher(),
                                   c.eraseToAnyPublisher(),
                                   d.eraseToAnyPublisher()])
                .start()
        }

        public func merge<P: Publisher>(with other: P) -> Publishers.Merge5<A, B, C, D, P>
            where D.Failure == P.Failure, D.Output == P.Output
        {
            return .init(a, b, c, d, other)
        }

        public func merge<Z: Publisher, Y: Publisher>(with z: Z, _ y: Y)
            -> Publishers.Merge6<A, B, C, D, Z, Y>
            where D.Failure == Z.Failure, D.Output == Z.Output,
                  Z.Failure == Y.Failure, Z.Output == Y.Output
        {
            return .init(a, b, c, d, z, y)
        }

        public func merge<Z: Publisher, Y: Publisher, X: Publisher>(with z: Z, _ y: Y, _ x: X)
            -> Publishers.Merge7<A, B, C, D, Z, Y, X>
            where D.Failure == Z.Failure, D.Output == Z.Output,
                  Z.Failure == Y.Failure, Z.Output == Y.Output,
                  Y.Failure == X.Failure, Y.Output == X.Output
        {
            return .init(a, b, c, d, z, y, x)
        }

        public func merge<Z: Publisher, Y: Publisher, X: Publisher, W: Publisher>(
            with z: Z, _ y: Y, _ x: X, _ w: W
        ) -> Publishers.Merge8<A, B, C, D, Z, Y, X, W>
            where D.Failure == Z.Failure, D.Output == Z.Output,
                  Z.Failure == Y.Failure, Z.Output == Y.Output,
                  Y.Failure == X.Failure, Y.Output == X.Output,
                  X.Failure == W.Failure, X.Output == W.Output
        {
            return .init(a, b, c, d, z, y, x, w)
        }
    }

    /// A publisher created by applying the merge function to five upstream publishers.
    public struct Merge5<A: Publisher, B: Publisher, C: Publisher, D: Publisher,
                         E: Publisher>: Publisher
        where A.Failure == B.Failure, A.Output == B.Output,
              B.Failure == C.Failure, B.Output == C.Output,
              C.Failure == D.Failure, C.Output == D.Output,
              D.Failure == E.Failure, D.Output == E.Output
    {
        public typealias Output = A.Output

        public typealias Failure = A.Failure

        public let a: A

        public let b: B

        public let c: C

        public let d: D

        public let e: E

        public init(_ a: A, _ b: B, _ c: C, _ d: D, _ e: E) {
            self.a = a
            self.b = b
            self.c = c
            self.d = d
            self.e = e
        }

        public func receive<Downstream: Subscriber>(subscriber: Downstream)
            where E.Failure == Downstream.Failure, E.Output == Downstream.Input
        {
            MergeInner(downstream: subscriber,
                       upstreams: [a.eraseToAnyPublisher(),
                                   b.eraseToAnyPublisher(),
                                   c.eraseToAnyPublisher(),
                                   d.eraseToAnyPublisher(),
                                   e.eraseToAnyPublisher()])
                .start()
        }

        public func merge<P: Publisher>(with other: P) -> Publishers.Merge6<A, B, C, D, E, P>
            where E.Failure == P.Failure, E.Output == P.Output
        {
            return .init(a, b, c, d, e, other)
        }

        public func merge<Z: Publisher, Y: Publisher>(with z: Z, _ y: Y)
            -> Publishers.Merge7<A, B, C, D, E, Z, Y>
            where E.Failure == Z.Failure, E.Output == Z.Output,
                  Z.Failure == Y.Failure, Z.Output == Y.Output
        {
            return .init(a, b, c, d, e, z, y)
        }

        public func merge<Z: Publisher, Y: Publisher, X: Publisher>(with z: Z, _ y: Y, _ x: X)
            -> Publishers.Merge8<A, B, C, D, E, Z, Y, X>
            where E.Failure == Z.Failure, E.Output == Z.Output,
                  Z.Failure == Y.Failure, Z.Output == Y.Output,
                  Y.Failure == X.Failure, Y.Output == X.Output
        {
            return .init(a, b, c, d, e, z, y, x)
        }
    }

    /// A publisher created by applying the merge function to six upstream publishers.
    public struct Merge6<A: Publisher, B: Publisher, C: Publisher, D: Publisher,
                         E: Publisher, F: Publisher>: Publisher
        where A.Failure == B.Failure, A.Output == B.Output,
              B.Failure == C.Failure, B.Output == C.Output,
              C.Failure == D.Failure, C.Output == D.Output,
              D.Failure == E.Failure, D.Output == E.Output,
              E.Failure == F.Failure, E.Output == F.Output
    {
        public typealias Output = A.Output

        public typealias Failure = A.Failure

        public let a: A

        public let b: B

        public let c: C

        public let d: D

        public let e: E

        public let f: F

        public init(_ a: A, _ b: B, _ c: C, _ d: D, _ e: E, _ f: F) {
            self.a = a
            self.b = b
            self.c = c
            self.d = d
            self.e = e
            self.f = f
        }

        public func receive<Downstream: Subscriber>(subscriber: Downstream)
            where F.Failure == Downstream.Failure, F.Output == Downstream.Input
        {
            MergeInner(downstream: subscriber,
                       upstreams: [a.eraseToAnyPublisher(),
                                   b.eraseToAnyPublisher(),
                                   c.eraseToAnyPublisher(),
                                   d.eraseToAnyPublisher(),
                                   e.eraseToAnyPublisher(),
                                   f.eraseToAnyPublisher()])
                .start()
        }

        public func merge<P: Publisher>(with other: P)
            -> Publishers.Merge7<A, B, C, D, E, F, P>
            where F.Failure == P.Failure, F.Output == P.Output
        {
            return .init(a, b, c, d, e, f, other)
        }

        public func merge<Z: Publisher, Y: Publisher>(with z: Z, _ y: Y)
            -> Publishers.Merge8<A, B, C, D, E, F, Z, Y>
            where F.Failure == Z.Failure, F.Output == Z.Output,
                  Z.Failure == Y.Failure, Z.Output == Y.Output
        {
            return .init(a, b, c, d, e, f, z, y)
        }
    }

    /// A publisher created by applying the merge function to seven upstream publishers.
    public struct Merge7<A: Publisher, B: Publisher, C: Publisher, D: Publisher,
                         E: Publisher, F: Publisher, G: Publisher>: Publisher
        where A.Failure == B.Failure, A.Output == B.Output,
              B.Failure == C.Failure, B.Output == C.Output,
              C.Failure == D.Failure, C.Output == D.Output,
              D.Failure == E.Failure, D.Output == E.Output,
              E.Failure == F.Failure, E.Output == F.Output,
              F.Failure == G.Failure, F.Output == G.Output
    {
        public typealias Output = A.Output

        public typealias Failure = A.Failure

        public let a: A

        public let b: B

        public let c: C

        public let d: D

        public let e: E

        public let f: F

        public let g: G

        public init(_ a: A, _ b: B, _ c: C, _ d: D, _ e: E, _ f: F, _ g: G) {
            self.a = a
            self.b = b
            self.c = c
            self.d = d
            self.e = e
            self.f = f
            self.g = g
        }

        public func receive<Downstream: Subscriber>(subscriber: Downstream)
            where G.Failure == Downstream.Failure, G.Output == Downstream.Input
        {
            MergeInner(downstream: subscriber,
                       upstreams: [a.eraseToAnyPublisher(),
                                   b.eraseToAnyPublisher(),
                                   c.eraseToAnyPublisher(),
                                   d.eraseToAnyPublisher(),
                                   e.eraseToAnyPublisher(),
                                   f.eraseToAnyPublisher(),
                                   g.eraseToAnyPublisher()])
                .start()
        }

        public func merge<P: Publisher>(with other: P)
            -> Publishers.Merge8<A, B, C, D, E, F, G, P>
            where G.Failure == P.Failure, G.Output == P.Output
        {
            return .init(a, b, c, d, e, f, g, other)
        }
    }

    /// A publisher created by applying the merge function to eight upstream publishers.
    public struct Merge8<A: Publisher, B: Publisher, C: Publisher, D: Publisher,
                         E: Publisher, F: Publisher, G: Publisher, H: Publisher>: Publisher
        where A.Failure == B.Failure, A.Output == B.Output,
              B.Failure == C.Failure, B.Output == C.Output,
              C.Failure == D.Failure, C.Output == D.Output,
              D.Failure == E.Failure, D.Output == E.Output,
              E.Failure == F.Failure, E.Output == F.Output,
              F.Failure == G.Failure, F.Output == G.Output,
              G.Failure == H.Failure, G.Output == H.Output
    {
        public typealias Output = A.Output

        public typealias Failure = A.Failure

        public let a: A

        public let b: B

        public let c: C

        public let d: D

        public let e: E

        public let f: F

        public let g: G

        public let h: H

        public init(_ a: A, _ b: B, _ c: C, _ d: D, _ e: E, _ f: F, _ g: G, _ h: H) {
            self.a = a
            self.b = b
            self.c = c
            self.d = d
            self.e = e
            self.f = f
            self.g = g
            self.h = h
        }

        public func receive<Downstream: Subscriber>(subscriber: Downstream)
            where H.Failure == Downstream.Failure, H.Output == Downstream.Input
        {
            MergeInner(downstream: subscriber,
                       upstreams: [a.eraseToAnyPublisher(),
                                   b.eraseToAnyPublisher(),
                                   c.eraseToAnyPublisher(),
                                   d.eraseToAnyPublisher(),
                                   e.eraseToAnyPublisher(),
                                   f.eraseToAnyPublisher(),
                                   g.eraseToAnyPublisher(),
                                   h.eraseToAnyPublisher()])
                .start()
        }
    }

    /// A publisher created by applying the merge function to an arbitrary number of
    /// upstream publishers.
    public struct MergeMany<Upstream: Publisher>: Publisher {

        public typealias Output = Upstream.Output

        public typealias Failure = Upstream.Failure

        public let publishers: [Upstream]

        public init(_ upstream: Upstream...) {
            publishers = upstream
        }

        public init<S: Swift.Sequence>(_ upstream: S) where Upstream == S.Element {
            publishers = Array(upstream)
        }

        public func receive<Downstream: Subscriber>(subscriber: Downstream)
            where Upstream.Failure == Downstream.Failure,
                  Upstream.Output == Downstream.Input
        {
            MergeInner(downstream: subscriber,
                       upstreams: publishers.map { $0.eraseToAnyPublisher() })
                .start()
        }

        public func merge(with other: Upstream) -> Publishers.MergeMany<Upstream> {
            return .init(publishers + [other])
        }
    }
}

extension Publisher {

    /// Combines elements from this publisher with those from another publisher,
    /// delivering an interleaved sequence of elements.
    public func merge<P: Publisher>(with other: P) -> Publishers.Merge<Self, P>
        where Failure == P.Failure, Output == P.Output
    {
        return .init(self, other)
    }

    /// Combines elements from this publisher with those from two other publishers,
    /// delivering an interleaved sequence of elements.
    public func merge<B: Publisher, C: Publisher>(with b: B, _ c: C)
        -> Publishers.Merge3<Self, B, C>
        where Failure == B.Failure, Output == B.Output,
              B.Failure == C.Failure, B.Output == C.Output
    {
        return .init(self, b, c)
    }

    /// Combines elements from this publisher with those from three other publishers,
    /// delivering an interleaved sequence of elements.
    public func merge<B: Publisher, C: Publisher, D: Publisher>(with b: B, _ c: C, _ d: D)
        -> Publishers.Merge4<Self, B, C, D>
        where Failure == B.Failure, Output == B.Output,
              B.Failure == C.Failure, B.Output == C.Output,
              C.Failure == D.Failure, C.Output == D.Output
    {
        return .init(self, b, c, d)
    }

    /// Combines elements from this publisher with those from four other publishers,
    /// delivering an interleaved sequence of elements.
    public func merge<B: Publisher, C: Publisher, D: Publisher, E: Publisher>(
        with b: B, _ c: C, _ d: D, _ e: E
    ) -> Publishers.Merge5<Self, B, C, D, E>
        where Failure == B.Failure, Output == B.Output,
              B.Failure == C.Failure, B.Output == C.Output,
              C.Failure == D.Failure, C.Output == D.Output,
              D.Failure == E.Failure, D.Output == E.Output
    {
        return .init(self, b, c, d, e)
    }

    /// Combines elements from this publisher with those from five other publishers,
    /// delivering an interleaved sequence of elements.
    public func merge<B: Publisher, C: Publisher, D: Publisher, E: Publisher, F: Publisher>(
        with b: B, _ c: C, _ d: D, _ e: E, _ f: F
    ) -> Publishers.Merge6<Self, B, C, D, E, F>
        where Failure == B.Failure, Output == B.Output,
              B.Failure == C.Failure, B.Output == C.Output,
              C.Failure == D.Failure, C.Output == D.Output,
              D.Failure == E.Failure, D.Output == E.Output,
              E.Failure == F.Failure, E.Output == F.Output
    {
        return .init(self, b, c, d, e, f)
    }

    /// Combines elements from this publisher with those from six other publishers,
    /// delivering an interleaved sequence of elements.
    public func merge<B: Publisher, C: Publisher, D: Publisher, E: Publisher, F: Publisher,
                      G: Publisher>(
        with b: B, _ c: C, _ d: D, _ e: E, _ f: F, _ g: G
    ) -> Publishers.Merge7<Self, B, C, D, E, F, G>
        where Failure == B.Failure, Output == B.Output,
              B.Failure == C.Failure, B.Output == C.Output,
              C.Failure == D.Failure, C.Output == D.Output,
              D.Failure == E.Failure, D.Output == E.Output,
              E.Failure == F.Failure, E.Output == F.Output,
              F.Failure == G.Failure, F.Output == G.Output
    {
        return .init(self, b, c, d, e, f, g)
    }

    /// Combines elements from this publisher with those from seven other publishers,
    /// delivering an interleaved sequence of elements.
    public func merge<B: Publisher, C: Publisher, D: Publisher, E: Publisher, F: Publisher,
                      G: Publisher, H: Publisher>(
        with b: B, _ c: C, _ d: D, _ e: E, _ f: F, _ g: G, _ h: H
    ) -> Publishers.Merge8<Self, B, C, D, E, F, G, H>
        where Failure == B.Failure, Output == B.Output,
              B.Failure == C.Failure, B.Output == C.Output,
              C.Failure == D.Failure, C.Output == D.Output,
              D.Failure == E.Failure, D.Output == E.Output,
              E.Failure == F.Failure, E.Output == F.Output,
              F.Failure == G.Failure, F.Output == G.Output,
              G.Failure == H.Failure, G.Output == H.Output
    {
        return .init(self, b, c, d, e, f, g, h)
    }

    /// Combines elements from this publisher with those from another publisher of
    /// the same type, delivering an interleaved sequence of elements.
    public func merge(with other: Self) -> Publishers.MergeMany<Self> {
        return .init(self, other)
    }
}

extension Publishers.Merge: Equatable where A: Equatable, B: Equatable {
    public static func == (lhs: Publishers.Merge<A, B>,
                           rhs: Publishers.Merge<A, B>) -> Bool {
        return lhs.a == rhs.a && lhs.b == rhs.b
    }
}

extension Publishers.Merge3: Equatable where A: Equatable, B: Equatable, C: Equatable {
    public static func == (lhs: Publishers.Merge3<A, B, C>,
                           rhs: Publishers.Merge3<A, B, C>) -> Bool {
        return lhs.a == rhs.a && lhs.b == rhs.b && lhs.c == rhs.c
    }
}

extension Publishers.Merge4: Equatable
    where A: Equatable, B: Equatable, C: Equatable, D: Equatable
{
    public static func == (lhs: Publishers.Merge4<A, B, C, D>,
                           rhs: Publishers.Merge4<A, B, C, D>) -> Bool {
        return lhs.a == rhs.a && lhs.b == rhs.b && lhs.c == rhs.c && lhs.d == rhs.d
    }
}

extension Publishers.Merge5: Equatable
    where A: Equatable, B: Equatable, C: Equatable, D: Equatable, E: Equatable
{
    public static func == (lhs: Publishers.Merge5<A, B, C, D, E>,
                           rhs: Publishers.Merge5<A, B, C, D, E>) -> Bool {
        return lhs.a == rhs.a && lhs.b == rhs.b && lhs.c == rhs.c && lhs.d == rhs.d &&
               lhs.e == rhs.e
    }
}

extension Publishers.Merge6: Equatable
    where A: Equatable, B: Equatable, C: Equatable, D: Equatable, E: Equatable, F: Equatable
{
    public static func == (lhs: Publishers.Merge6<A, B, C, D, E, F>,
                           rhs: Publishers.Merge6<A, B, C, D, E, F>) -> Bool {
        return lhs.a == rhs.a && lhs.b == rhs.b && lhs.c == rhs.c && lhs.d == rhs.d &&
               lhs.e == rhs.e && lhs.f == rhs.f
    }
}

extension Publishers.Merge7: Equatable
    where A: Equatable, B: Equatable, C: Equatable, D: Equatable, E: Equatable,
          F: Equatable, G: Equatable
{
    public static func == (lhs: Publishers.Merge7<A, B, C, D, E, F, G>,
                           rhs: Publishers.Merge7<A, B, C, D, E, F, G>) -> Bool {
        return lhs.a == rhs.a && lhs.b == rhs.b && lhs.c == rhs.c && lhs.d == rhs.d &&
               lhs.e == rhs.e && lhs.f == rhs.f && lhs.g == rhs.g
    }
}

extension Publishers.Merge8: Equatable
    where A: Equatable, B: Equatable, C: Equatable, D: Equatable, E: Equatable,
          F: Equatable, G: Equatable, H: Equatable
{
    public static func == (lhs: Publishers.Merge8<A, B, C, D, E, F, G, H>,
                           rhs: Publishers.Merge8<A, B, C, D, E, F, G, H>) -> Bool {
        return lhs.a == rhs.a && lhs.b == rhs.b && lhs.c == rhs.c && lhs.d == rhs.d &&
               lhs.e == rhs.e && lhs.f == rhs.f && lhs.g == rhs.g && lhs.h == rhs.h
    }
}

extension Publishers.MergeMany: Equatable where Upstream: Equatable {
    public static func == (lhs: Publishers.MergeMany<Upstream>,
                           rhs: Publishers.MergeMany<Upstream>) -> Bool {
        return lhs.publishers == rhs.publishers
    }
}

// MARK: - Implementation

/// The subscription handed to the downstream of every Merge publisher. One `Side` per
/// upstream forwards into it. Values arriving while the downstream has no demand are
/// buffered in arrival order; each upstream is asked for one value at a time unless the
/// downstream demand is unlimited, in which case the upstreams are too.
private final class MergeInner<Downstream: Subscriber>
    : Subscription,
      CustomStringConvertible,
      CustomReflectable,
      CustomPlaygroundDisplayConvertible
{
    typealias Output = Downstream.Input
    typealias Failure = Downstream.Failure

    private let lock = UnfairLock.allocate()
    private let downstreamLock = UnfairRecursiveLock.allocate()
    private var downstream: Downstream?
    private let upstreams: [AnyPublisher<Output, Failure>]
    private var subscriptions: [Subscription?]
    private var unlimited: [Bool]
    private var demand = Subscribers.Demand.none
    private var buffer: [(side: Int, value: Output)] = []
    private var active: Int
    private var terminated = false

    init(downstream: Downstream, upstreams: [AnyPublisher<Output, Failure>]) {
        self.downstream = downstream
        self.upstreams = upstreams
        subscriptions = Array(repeating: nil, count: upstreams.count)
        unlimited = Array(repeating: false, count: upstreams.count)
        active = upstreams.count
    }

    deinit {
        lock.deallocate()
        downstreamLock.deallocate()
    }

    func start() {
        guard let downstream = downstream else { return }
        downstreamLock.lock()
        downstream.receive(subscription: self)
        downstreamLock.unlock()
        if upstreams.isEmpty {
            finishIfDone()
            return
        }
        for (index, upstream) in upstreams.enumerated() {
            upstream.subscribe(Side(parent: self, index: index))
        }
    }

    // MARK: Side events

    fileprivate func receive(subscription: Subscription, from side: Int) {
        lock.lock()
        guard !terminated, subscriptions[side] == nil else {
            lock.unlock()
            subscription.cancel()
            return
        }
        subscriptions[side] = subscription
        let wantsUnlimited = demand == .unlimited
        unlimited[side] = wantsUnlimited
        lock.unlock()
        subscription.request(wantsUnlimited ? .unlimited : .max(1))
    }

    fileprivate func receive(_ input: Output, from side: Int) -> Subscribers.Demand {
        lock.lock()
        guard !terminated, let downstream = downstream else {
            lock.unlock()
            return .none
        }
        if demand > 0 && buffer.isEmpty {
            demand -= 1
            lock.unlock()
            downstreamLock.lock()
            let newDemand = downstream.receive(input)
            downstreamLock.unlock()
            lock.lock()
            demand += newDemand
            let more = unlimited[side] ? Subscribers.Demand.none : .max(1)
            let toUnlimit = newDemand == .unlimited ? subscriptionsToUnlimit() : []
            lock.unlock()
            toUnlimit.forEach { $0.request(.unlimited) }
            return more
        } else {
            buffer.append((side, input))
            lock.unlock()
            return .none
        }
    }

    fileprivate func receive(completion: Subscribers.Completion<Failure>, from side: Int) {
        lock.lock()
        guard !terminated else {
            lock.unlock()
            return
        }
        subscriptions[side] = nil
        switch completion {
        case .failure:
            terminated = true
            let downstream = self.downstream.take()
            let others = subscriptions.compactMap { $0 }
            subscriptions = Array(repeating: nil, count: subscriptions.count)
            buffer.removeAll()
            lock.unlock()
            others.forEach { $0.cancel() }
            downstreamLock.lock()
            downstream?.receive(completion: completion)
            downstreamLock.unlock()
        case .finished:
            active -= 1
            lock.unlock()
            finishIfDone()
        }
    }

    // MARK: Subscription

    func request(_ demand: Subscribers.Demand) {
        demand.assertNonZero()
        lock.lock()
        guard !terminated, downstream != nil else {
            lock.unlock()
            return
        }
        self.demand += demand
        let toUnlimit = demand == .unlimited ? subscriptionsToUnlimit() : []
        lock.unlock()
        toUnlimit.forEach { $0.request(.unlimited) }
        drain()
        finishIfDone()
    }

    func cancel() {
        lock.lock()
        terminated = true
        downstream = nil
        let subscriptions = self.subscriptions.compactMap { $0 }
        self.subscriptions = Array(repeating: nil, count: self.subscriptions.count)
        buffer.removeAll()
        lock.unlock()
        subscriptions.forEach { $0.cancel() }
    }

    // MARK: Private

    /// Caller holds `lock`. Marks every side unlimited and returns the subscriptions
    /// that still need to be told.
    private func subscriptionsToUnlimit() -> [Subscription] {
        var result: [Subscription] = []
        for index in subscriptions.indices where !unlimited[index] {
            unlimited[index] = true
            if let subscription = subscriptions[index] {
                result.append(subscription)
            }
        }
        return result
    }

    /// Delivers buffered values while there is demand.
    private func drain() {
        while true {
            lock.lock()
            guard !terminated, let downstream = downstream, demand > 0,
                  !buffer.isEmpty
            else {
                lock.unlock()
                return
            }
            let (side, value) = buffer.removeFirst()
            demand -= 1
            lock.unlock()
            downstreamLock.lock()
            let newDemand = downstream.receive(value)
            downstreamLock.unlock()
            lock.lock()
            demand += newDemand
            let more = unlimited[side] ? nil : subscriptions[side]
            let toUnlimit = newDemand == .unlimited ? subscriptionsToUnlimit() : []
            lock.unlock()
            toUnlimit.forEach { $0.request(.unlimited) }
            more?.request(.max(1))
        }
    }

    private func finishIfDone() {
        lock.lock()
        guard !terminated, active == 0, buffer.isEmpty,
              let downstream = self.downstream.take()
        else {
            lock.unlock()
            return
        }
        terminated = true
        lock.unlock()
        downstreamLock.lock()
        downstream.receive(completion: .finished)
        downstreamLock.unlock()
    }

    var description: String { return "Merge" }

    var customMirror: Mirror {
        lock.lock()
        defer { lock.unlock() }
        let children: [Mirror.Child] = [
            ("downstream", downstream as Any),
            ("demand", demand),
            ("buffered", buffer.count),
            ("active", active)
        ]
        return Mirror(self, children: children)
    }

    var playgroundDescription: Any { return description }

    /// The subscriber attached to one upstream.
    private final class Side: Subscriber {
        typealias Input = Output

        private let parent: MergeInner
        private let index: Int
        let combineIdentifier = CombineIdentifier()

        init(parent: MergeInner, index: Int) {
            self.parent = parent
            self.index = index
        }

        func receive(subscription: Subscription) {
            parent.receive(subscription: subscription, from: index)
        }

        func receive(_ input: Input) -> Subscribers.Demand {
            return parent.receive(input, from: index)
        }

        func receive(completion: Subscribers.Completion<Failure>) {
            parent.receive(completion: completion, from: index)
        }
    }
}
