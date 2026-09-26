import Foundation

/// kotlin.random.Random(seed): Marsaglia's xorwow, bit for bit, so the instrument's fixed star
/// field and dust lane fall exactly where they do on Android.
struct KotlinRandom {
    private var x: Int32, y: Int32, z: Int32, w: Int32, v: Int32, addend: Int32

    /// Random(seed: Int).
    init(seed: Int32) {
        self.init(seed1: seed, seed2: seed >> 31)
    }

    private init(seed1: Int32, seed2: Int32) {
        x = seed1
        y = seed2
        z = 0
        w = 0
        v = ~seed1
        addend = (seed1 << 10) ^ Int32(bitPattern: UInt32(bitPattern: seed2) >> 4)
        precondition((x | y | z | w | v) != 0, "Initial state must have at least one non-zero element.")
        // As Kotlin does, discard the first 64 values: trivial seeds start with zeroed upper bits.
        for _ in 0..<64 { _ = nextInt() }
    }

    mutating func nextInt() -> Int32 {
        var t = x
        t = t ^ Int32(bitPattern: UInt32(bitPattern: t) >> 2)
        x = y
        y = z
        z = w
        let v0 = v
        w = v0
        t = (t ^ (t &<< 1)) ^ v0 ^ (v0 &<< 4)
        v = t
        addend = addend &+ 362_437
        return t &+ addend
    }

    mutating func nextBits(_ bitCount: Int) -> Int32 {
        let value = UInt32(bitPattern: nextInt()) >> UInt32(32 - bitCount)
        return bitCount == 0 ? 0 : Int32(bitPattern: value)
    }

    /// nextFloat(): 24 random bits over 2^24.
    mutating func nextFloat() -> Float {
        Float(nextBits(24)) / Float(1 << 24)
    }

    /// nextInt(until): uniform in 0..<until.
    mutating func nextInt(_ until: Int32) -> Int32 {
        precondition(until > 0)
        let n = until
        if n & -n == n {
            let bitCount = 31 - n.leadingZeroBitCount
            return nextBits(bitCount)
        }
        var bits: Int32
        var value: Int32
        repeat {
            bits = Int32(bitPattern: UInt32(bitPattern: nextInt()) >> 1)
            value = bits % n
        } while bits &- value &+ (n - 1) < 0
        return value
    }
}
