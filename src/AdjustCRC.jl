"""
This module exports two functions, `adjust_crc` and `adjust_crc!`,
which allow you to write 4 bytes to a file or array in order to
adjust the 32-bit CRC checksum (either CRC32 or CRC32c) to equal
any desired value.

This is useful, for example, to store the checksum of data within
the data itself, or simply to set the checksum to be a hard-coded
value like `0x01020304` for ease of later checks.
"""
module AdjustCRC

export adjust_crc, adjust_crc!
import CRC32, CRC32c

# Code to adjust a byte array to have an arbitrary given crc, by
# injecting 4 bytes at fixpos, following:
#     Martin Stigge, Henryk Plötz, Wolf Müller, & Jens-Peter Redlich,
#     "Reversing CRC — Theory and Practice,"
#     HU Berlin Public Report SAR-PR-2006-05 (May 2006).
# This is useful if you want to store the CRC of a file in the file.

const POLY32  = 0xedb88320 # CRC-32 (ISO 3309 / ITU-T V.42 / CRC-32-IEEE) polynomial
const POLY32c = 0x82f63b78 # CRC-32C (iSCSI) polynomial in reversed bit order.

# reversed CRC table: Algorithm 5 from Stigge et al.
function gen_revtable(poly::UInt32)
    table = Vector{UInt32}(undef, 256)
    for index = UInt32(0):UInt32(255)
        crc = index << 24;
        for i = 1:8
            crc = !iszero(crc & 0x80000000) ? ((crc ⊻ poly) << 1) + 0x01 : crc << 1;
        end
        table[index+1] = crc;
    end
    return table
end

const REVTABLE32  = gen_revtable(POLY32)  # reversed CRC-32 table
const REVTABLE32c = gen_revtable(POLY32c) # reversed CRC-32C table

revtable(::typeof(CRC32.crc32))   = REVTABLE32
revtable(::typeof(CRC32c.crc32c)) = REVTABLE32c

# Table-driven "backwards" calculation of CRC: Algorithm 6 from Stigge et al.
function bwcrc(a::AbstractVector{UInt8}, crc::UInt32, revtable::AbstractVector{UInt32})
    crc = crc ⊻ 0xffffffff
    for i = reverse(eachindex(a))
        crc = (crc << 8) ⊻ revtable[(crc >> 24) + 1] ⊻ a[i]
    end
    return crc
end

"""
    adjust_crc!(crc, a::AbstractVector{UInt8}, wantcrc::UInt32, fixpos::Integer)

Write 4 bytes to `a[fixpos:fixpos+3]` so that `crc(a)` becomes equal to `wantcrc`.
This is especially useful if you want to store the checksum of some data *within
the data* itself, or simply to set the crc to an arbitrary predetermined value.
Here, `crc` is a function that computes a 32-bit CRC checksum:
either `crc32c` from the `CRC32c` standard library or `crc32`
from the [CRC32.jl package](https://github.com/JuliaIO/CRC32.jl).

Note that the `adjust_crc!` function is most efficient when `fixpos` is
close to the end of the array `a`, and is slowest for `fixpos` near the beginning.
(Though in all cases the cost should scale linearly with `length(a)`.)
See also [`adjust_crc`](@ref) to append similar padding bytes to the end of
a file or I/O stream (which has the advantage of not requiring you to read the
entire file into memory at once).
"""
function adjust_crc!(crc::F, a::AbstractVector{UInt8}, wantcrc::UInt32, fixpos::Integer) where {F}
    # store v in little-endian order at b[k:k+3]
    function store_le!(b::AbstractVector{UInt8}, k::Integer, v::UInt32)
        @inbounds b[k],b[k+1],b[k+2],b[k+3] =
            v%UInt8, (v>>8)%UInt8, (v>>16)%UInt8, (v>>24)%UInt8
    end

    # Algorithm 8 from Stigge et al.
    checkbounds(a, fixpos:fixpos+3)
    @views store_le!(a, fixpos, crc(a[firstindex(a):fixpos-1]) ⊻ 0xffffffff)
    @views store_le!(a, fixpos, bwcrc(a[fixpos:end], wantcrc, revtable(crc)))
    return a
end

"""
    adjust_crc(crc, filename::AbstractString, wantcrc::UInt32)
    adjust_crc(crc, io::IO, wantcrc::UInt32)

Write 4 bytes of "padding" to the *end* of the the I/O stream `io`
(which *must* be seekable and read/write) or the file `filename`, in order
to cause the `crc` checksum of the whole stream/file to equal `wantcrc`.
Here, `crc` is a function that computes a 32-bit CRC checksum:
either `crc32c` from the `CRC32c` standard library or `crc32`
from the [CRC32.jl package](https://github.com/JuliaIO/CRC32.jl).

(This is mainly useful if you want to store the checksum of the file *within the file*:
simply set `wantcrc` to be an arbitrary number, such as `rand(UInt32)`, store it within
the file as desired, and then call `adjust_crc` to write padding bytes that force
the checksum to match `wantcrc`.  Even more simply, you could force all of your files
to have a checksum that matches a hard-coded value like `0x01020304`, in which case you
don't need to store the checksum in the file itself.)
See also [`adjust_crc!`](@ref) to write similar padding bytes to an arbitrary
position within an array.
"""
function adjust_crc(crc::F, io::IO, wantcrc::UInt32) where {F}
    le(v::UInt32) = [v%UInt8, (v>>8)%UInt8, (v>>16)%UInt8, (v>>24)%UInt8]

    isreadable(io) || throw(ArgumentError("stream must be readable"))
    iswritable(io) || throw(ArgumentError("stream must be writable"))

    # specialized version of adjust_crc32c! for writing to end
    write(io, htol(bwcrc(le(crc(seekstart(io)) ⊻ 0xffffffff), wantcrc, revtable(crc))))
    return io
end

adjust_crc(crc::F, filename::AbstractString, wantcrc::UInt32) where {F} =
    open(io -> adjust_crc(crc, io, wantcrc), filename, "r+")

end
