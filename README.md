# AdjustCRC

[![Build Status](https://github.com/stevengj/AdjustCRC.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/stevengj/AdjustCRC.jl/actions/workflows/CI.yml?query=branch%3Amain)

This module exports two functions, `adjust_crc` and `adjust_crc!`,
which allow you to write 4 bytes to a file or array in order to
adjust the [32-bit CRC checksum](https://en.wikipedia.org/wiki/Cyclic_redundancy_check)
(either [CRC32](https://github.com/JuliaIO/CRC32.jl) or
[CRC32c](https://docs.julialang.org/en/v1/stdlib/CRC32c/))
to equal any desired value.

This is useful, for example, to store the checksum of data within
the data itself, or simply to set the checksum to be a hard-coded
value like `0x01020304` for ease of later checks.

## Functions

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
See also `adjust_crc`, below, to append similar padding bytes to the end of
a file or I/O stream (which has the advantage of not requiring you to read the
entire file into memory at once).

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
See also `adjust_crc!`, above, to write similar padding bytes to an arbitrary
position within an array.

## Examples

For example, suppose that we are writing some data to a file, and want to force the
file's CRC-32c checksum to be `0x01020304`, using the [CRC32c standard library](https://docs.julialang.org/en/v1/stdlib/CRC32c/) (which should usually be the fastest CRC available in Julia).
Then we can use `adjust_crc` to append 4 bytes which force this checksum, either while
we have the file still open or afterwards given the filename:

```jl
julia> open("foo.dat", "w+") do io   # create/open foo.dat for reading and writing
           println(io, "Hello, world!\n")
           adjust_crc(crc32c, io, 0x01020304)
       end
IOStream(<file foo.dat>)

julia> open(crc32c, "foo.dat") # check the CRC-32c checksum of the file "foo.dat"
0x01020304

julia> read("foo.dat", String) # note that it has 4 bytes of "garbage" at the end
"Hello, world!\n\n\xf3B_\xe4"
```

You can also pass a filename to `adjust_crc` to modify a file after the fact:
```jl
julia> adjust_crc(crc32c, "foo.dat", 0x05060708)
IOStream(<file foo.dat>)

julia> open(crc32c, "foo.dat") # chck that it has the new checksum
0x05060708

julia> read("foo.dat", String) # another 4 bytes of "garbage" have been appended
"Hello, world!\n\n\xf3B_\xe4ޕ\x15\e"
```

The `adjust_crc` function always appends 4 bytes to the *end* of a file or stream
in order to change the CRC to the desired value.   If you have an array of bytes,
you can also write these 4 "garbage" bytes *anywhere* in the array to adjust its
CRC using the `adjust_crc!` function.  For example, the following overwrites 4 bytes of
the string `"Hello, world!"` starting at the 8th byte (`'w'`) to make the checksum
equal `0x01020304`:

```jl
julia> bytes = Vector{UInt8}("Hello, world!") # a string converted to mutable bytes
13-element Vector{UInt8}:
 0x48
 0x65
 0x6c
 0x6c
 0x6f
 0x2c
 0x20
 0x77
 0x6f
 0x72
 0x6c
 0x64
 0x21

julia> adjust_crc!(crc32c, bytes, 0x01020304, 8) # adjust CRC to 0x01020304 via bytes[8:11]
13-element Vector{UInt8}:
 0x48
 0x65
 0x6c
 0x6c
 0x6f
 0x2c
 0x20
 0xf3
 0xe7
 0xf1
 0xe6
 0x64
 0x21

julia> s = String(bytes) # let's view the new bytes as a string; note the 4 "garbage" bytes
"Hello, \xf3\xe7\xf1\xe6d!"

julia> crc32c(s) # check that it has the desired CRC
0x01020304
```

All of the above examples used the CRC-32c checksum by passing the `crc32c` argument.
You can instead do the same thing with the CRC-32 (ISO 3309 / ITU-T V.42 / CRC-32-IEEE)
checksum by doing `import CRC32` (from [CRC32.jl](https://github.com/JuliaIO/CRC32.jl))
and passing `crc32` instead.

## Acknowledgements

This package was written by [Steven G. Johnson](https://math.mit.edu/~stevenj/) based
on the algorithm described in:

* Martin Stigge, Henryk Plötz, Wolf Müller, and Jens-Peter Redlich, [Reversing CRC – Theory and Practice](https://sar.informatik.hu-berlin.de/research/publications/SAR-PR-2006-05/SAR-PR-2006-05_.pdf), HU Berlin Public Report SAR-PR-2006-05 (May 2006).

as suggested [on StackOverflow](https://stackoverflow.com/questions/1514040/reversing-crc32) by Jeremy Adsitt and others.
