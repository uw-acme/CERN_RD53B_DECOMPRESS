# CERN_RD53B_decompress
VHDL code for FPGA to de-compress (decode) the RD53B ASIC compressed data output 

RD53B data consists of a series of 'hits'.  A hit is composed of a 16-bit data block, called a 'qrow', the qrow location (row,column) and a 'time-over-threshold' (ToT) value for each bit in the qrow data.  The compressed qrow data can vary in length from 4 bits to 30 bits, with two flags indicating incrementing row values or new column values, and only contains non-zero ToT values. The resulting compressed data for one hit can vary between 16 and 110 bits. 
The compressed data is output in a series of 63-bit words which are serialized and transmitted from the RD53B ASIC.  
The receiving device must convert the serial stream back into 63-bit words before it can be decompressed.
The code in the repo does not serialize/deserialize the data. The block which generates test data outputs 63-bit data which is then supplied directly to the decompressors. The ser/des steps are not necessary for testing the algorithms.
