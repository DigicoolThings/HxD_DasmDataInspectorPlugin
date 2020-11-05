# Disassembly Plugin for HxD's Data inspector

This plugin is for Maël Hörz's excellant HxD hex and disk editor, which is available at: http://mh-nexus.de/hxd

## Background

I came across HxD while looking for a good hex editor, to allow visually comparing & analysing the differences between some retro Motorola MC6809 Monitor ROM images.

I was immediately impressed that Maël had included support for Motorola S-record files, and when I noticed the Data inspector included x86 Disassembly I immediately thought how useful 6809 Disassembly would be.
As I was seeing byte differences in my 6809 ROM comparisons, I was having to manually identify what the code differences were.

I initially looked for a pre-written Disassembler that I could integrate via Maël's published plugin framework: https://github.com/maelh/hxd-plugin-framework   

But I quickly came to the conclusion that there wasn't really anything substantial that I could (relatively easily) migrate for this purpose.
Plus, with my retro CPU interests, I could see that I'd potentially want to also add 6800 and 6502 code disassembly (maybe even 68000?), and looking at existing disassemblers, I really didn't like the "hard-coded" processor specific parsing approach.
  
## Implementation

To allow support for different CPU instruction Disassembly, I decided to implement a generic Disassembly plugin, that would allow additional CPU's to be supported by dropping-in new CPU definition files.

In other words, create a Disassembly plugin that anyone could add support for another CPU, without needing to write a whole new instruction disassembler / without having to make any code changes.

To achieve this, the plugin .dll (DasmDataInspectorPlugin.dll) references a .ini file (DasmDataInspectorPlugin.ini) for parameters, including details of the configured CPU's / Disassembly types.
For each configured CPU, a .csv based instruction definition file is also included.

To get started, I've initially created a Motorola MC6800 definition file as: Dasm6800.csv
I've also started on a MC6809 definition file, and I'm also planning a 6502 definition file.

To assist with debugging your own definition .csv files (or any changes you might want to make), the .ini file provides for a log file to be enabled. This provides visibility of the .csv file parsing and format errors (typos?) that are identified.

Note that while this implementation provides great flexibility for adding additional CPU Disassembly support, it's target audience is retro microprocessors. These generally have relatively simple instruction sets and addressing modes, which the definition files easily cater for.
However, I suspect limitation may be found if attempting to define more advanced / modern ISA's. Specifically, where a CPU has a significantly more complex instruction set, resulting in an excesively large number of resulting possible opcode + operand combinations.    

## Installation

As per Maël's instructions for the plugin framework, the files should all be installed into a "Plugins" sub-directory of your HxD installation directory.

First select either the Win64 or Win32 folder .dll version (based on your Windows installation), and copy this folder into your HxD installation directory.
Then also copy the Common folder, which contains the DasmDataInspectorPlugin.ini and CPU definition .csv files.

## Configuration

Please refer to the .ini file for documentation of the various settings included. Hopefully this should be self explanatory.

The .csv definition files (configured and referenced from the .ini file), hopefully have a self explanatory header line. Note this header line is purely optional, and is just included for readability / reference. 

## CSV file columns

- OpcodeBytes: The fixed (static) Hex bytes that comprise each unique instruction opcode. 
- OperandBytes: Any additional Hex Bytes that comprise the instruction Operand. Multi-byte Operands are specified with the target CPU's appropriate Endianness (which is specified in the .ini file).  
- OperandArgumentMask: The Hex Mask that should be used to extract any Argument from the Operand Bytes. Note that the inverted Mask also effectively defines any fixed (static) portion of the Operand. 
- ArgumentHexDec: Determines if the extracted Argument should be rendered in Hex or Decimal format.
- ArgumentSignedUnsigned: Determines if the extracted Argument should be treated as a Signed or Unsigned value. 
- DasmString: The decoded Disassembly string that is to be rendered in the data inspector. The .ini file specifies a wildcard (char or string), which you include to identify where the extracted / formatted Argument should be substituted into the string. 

Reviewing the above in combination with the included (completed) Dasm6800.csv file should clarify the definition file structure. 

## Features

- Supports any byte size Opcode (and optional Operand size).

- Configurable per CPU, for either Little Endian or Big Endian CPU Operand / Argument byte sequences.

- Supports Operand Argument extraction and automatic normalisation as either 8-bit, 16-bit, 32-bit or 64-bit values.

- Configurable per Opcode + Operand, for Unsigned or Signed Arguments.

- Configurable per Opcode + Operand, for Argument rendering in either Hex or Decimal format. For example, Address or data references would logically be rendered in their native Hex format, however relative offsets are perhaps better rendered in Decimal for easier interpretation.

## License

HxD Plugin Framework is Copyright (C) 2019-2020 Maël Hörz. The plugin framework is licensed under the MPL. 

This Disassembly Plugin is distributed as per the MPL Larger Work definition and [licensed under the Apache License 2.0](LICENSE)

## Contact

For bugs and CPU definition discussion, please use the issue tracker on GitHub.

There is also discussion on the forum: https://forum.mh-nexus.de
