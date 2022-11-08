
This block decodes a single stream of compressed/encoded 'hits'. 
Each 'hit' consists of addresses, hitmaps and ToTs.
The stream begins with some optional header information (chip_id and a 'tag')


Address length can vary between 2,8,10,16.
Encoded hitmap length can vary from 4 to 30 bits
ToT length can vary from 4 to 64 bits in steps of 4.
Min encoded hit length is 2+4+4 = 10.
Max encoded hit length is 16+30+64 = 110.

The block can output a decoded hit every eight clock cycles.
The input FIFO will overflow if the input data arrives faster than it can be processed.
It is difficult to pick a size for the input buffer since one input word could contain 6 
entire 10-bit hits, requiring 6x8 = 42 clock cycles to process, or just 63 bits of a 110-bit hit.

-- Input is over a 63-bit bus with an additional 'new-stream' bit. 
-- Data is initially buffered in a FIFO and then read out into a shift register (sreg) whenever the register
-- has space for 63 new bits. Initially 3 words are read into sreg[188:126], sreg[125:63] and sreg[62:0]
-- After each hit is decoded, from the sreg MSBs, we check to see if the 
-- sreg can be shifted left by 63 bits so that a new word can be read from the input FIFO.
-- Shifts can only occur in blocks of 63. The sreg_ptr keeps track of where the next hits address field starts.
-- The sreg_ptr starts at sreg[188]. If a 10-bit hit is consumed then sreg_ptr will be moved to (188-10) 178.
-- A second hit of 42 bits (say) will move the pointer to (178-48) 136.
-- A third hit of 31 bits (say) will move the pointer to 105. Once the pointer is below (188-63) = 125 then
-- sreg will be shifted left by 63 bits, a new word will be read from the FIFO into sreg[62:0] and the pointer
-- moves to (105+63) 168.  This is the location of the MSB of the next address block. 

-- If the MSBs are 6, or more, zeros then there are no more hits and this marks the end of the stream.
-- 

*** Internal tags (11-bit beginning "111") are not currently supported
