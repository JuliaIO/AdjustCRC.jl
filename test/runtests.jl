using AdjustCRC, Test
import CRC32, CRC32c

@testset "adjust_crc" begin
    wantcrc = 0x01020304
    for crc in (CRC32c.crc32c, CRC32.crc32)
        for fixpos = 1:98
            data = adjust_crc!(crc, rand(UInt8, 101), wantcrc, fixpos)
            @test crc(data) == wantcrc
        end
        @test_throws BoundsError adjust_crc!(crc, rand(UInt8, 101), wantcrc, 0)
        @test_throws BoundsError adjust_crc!(crc, rand(UInt8, 101), wantcrc, 99)

        let f = tempname()
            try
                write(f, rand(UInt8, 101))
                adjust_crc(crc, f, wantcrc)
                @test open(crc, f) == wantcrc
            finally
                rm(f, force=true)
            end
        end
    end
end
