# Disassembly Plugin for HxD's Data inspector

This plugin is for Maël Hörz's excellant HxD hex and disk editor, which is available at: http://mh-nexus.de/hxd

This plugin is compiled for HxD v2.5.0.0

## Background

I came across HxD while looking for a good hex editor, to allow visually comparing & analysing the differences between some retro Motorola MC6809 Monitor ROM images.

I was immediately impressed that Maël had included support for Motorola S-record files, and when I noticed the Data inspector included x86 Disassembly I immediately thought how useful 6809 Disassembly would be.
As I was seeing byte differences in my 6809 ROM comparisons, I was having to manually identify what the code differences were.

I initially looked for a pre-written Disassembler that I could integrate via Maël's published plugin framework: https://github.com/maelh/hxd-plugin-framework

But I quickly came to the conclusion that there wasn't really anything substantial that I could (relatively easily) migrate for this purpose.
Plus, with my retro CPU interests, I could see that I'd potentially want to also add 6800 and 6502 code disassembly (ed. which I have now done), and maybe even 68000, and looking at existing disassemblers, I really didn't like the "hard-coded" processor specific parsing approach.
  
## Implementation

To allow support for different CPU instruction Disassembly, I decided to implement a generic Disassembly plugin, that would allow additional CPU's to be supported by dropping-in new CPU definition files.

In other words, create a Disassembly plugin that anyone could add support for another CPU, without needing to write a whole new instruction disassembler / without having to make any code changes.

To achieve this, the plugin .dll (DasmDataInspectorPlugin.dll) references a .ini file (DasmDataInspectorPlugin.ini) for parameters, including details of the configured CPU's / Disassembly types.
For each configured CPU, a .csv based instruction definition file is also included.

To get started, I initially created a Motorola MC6800 definition file as: Dasm6800.csv
I've now also added several other processor definition files including 6502 family etc. (refer below), and also the more complex MC6809 8/16 bit processor definition file.

To assist with debugging your own definition .csv files (or any changes you might want to make), the .ini file provides for a log file to be enabled. This provides visibility of the .csv file parsing and format errors (typos?) that are identified.

Note that while this implementation provides great flexibility for adding additional CPU Disassembly support, it's target audience is retro microprocessors. These generally have relatively simple instruction sets and addressing modes, which the definition files easily cater for.
However, I suspect limitation may be found if attempting to define more advanced / modern ISA's. Specifically, where a CPU has a significantly more complex instruction set, resulting in an excessively large number of resulting possible opcode + operand combinations.

## Installation

Firstly, ensure you are running HxD 2.5.0.0 version.  This plugin is currently compiled for 2.5.0.0.  If a later HxD version requires changes to the plug-in interface, I will update the plugin here (as required).

As per Maël's instructions for the plugin framework, the files should all be installed into a "Plugins" sub-directory of your HxD installation directory.

First select either the Win64 or Win32 folder .dll version (based on your Windows installation), and copy the content of this folder into your HxD installation directory, creating (or updating) the "Plugins" sub-directory of your HxD installation directory.

Then also copy the contents of the Common folder, which contains the DasmDataInspectorPlugin.ini and the various CPU definition .csv files (once again, in the "Plugins" sub-directory).

Finally (optional - but recommended!), you can edit the DasmDataInspectorPlugin.ini file to include only the specific DasmTypes that you currently require or are interest in.  As per the documented .ini file, you can have up to 8 different Disassembly types at a time, however each one adds some HxD start-up time overhead as the definition files are loaded and parsed. Therefore, depending on your system performance, you may not wish to load all (or multiple) DasmTypes.  

## Configuration

Further to the above note on DasmTypes, please refer to the .ini file for documentation on the various settings included. Hopefully this should all be self explanatory.

The .csv definition files (configured and referenced from the .ini file), have relatively self explanatory column titles in the header line.  Note this header line is purely optional, and is just included for readability / reference. Leaving the header line in place has no impact on load time.

## CSV file column descriptions

- OpcodeBytes: The fixed (static) bytes, specified in Hex, that comprise each unique instruction Opcode.
- OperandBytes: Any additional Hex Bytes that make up the full instruction and contain the instruction Operand(s). Multi-byte Operands are specified in the byte sequence that they appear in memory. The extracted Operand(s) will however respect the target CPU's Endianness (specified in the .ini file).
- FirstOperandMask: The Hex bit mask that identifies the first Operand to be extracted from the Operand Bytes.
- FirstOperandHexDec: Determines if the extracted first Operand should be rendered in Hex (`H`) or Decimal (`D`) format.
- FirstOperandSignedUnsigned: Determines if the extracted first Operand should be treated as a Signed (`S`) or Unsigned (`U`) value. Typically, Signed is used for Relative reference Operands.  
- SecondOperandMask: As for FirstOperandMask, this is the Hex bit mask that identifies any required second Operand to be extracted from the Operand Bytes.
- SecondOperandHexDec: As above for the first Operand, this determines if any extracted second Operand should be rendered in Hex or Decimal format.
- SecondOperandSignedUnsigned: As above for the first Operand, this determines if any extracted second Operand should be treated as a Signed or Unsigned value.
- AssemblyString: The Disassembled instruction string that is to be rendered in the HxD data inspector. The .ini file specifies first and second Operand wildcard characters (or strings), which you include to identify where the extracted / formatted Operand(s) should be substituted into the string.

Reviewing the above, in combination with the various included (completed) .csv files, should help clarify the definition file structure.

## Features

- Supports any byte count sized Opcode and optional Operand byte count.

- Configurable per CPU, for either Little Endian or Big Endian Operand byte sequences.

- Supports extraction of up to two Operands per instruction, with automatic byte normalisation of each extracted Operand as being 1 to 8 bytes long (maximum of 64-bit Operands supported). For example, Operand masks of 8 bits or less would be rendered as a single byte, and a 24 bit Operand would be appropriately rendered as 3 bytes etc.  

- Configurable, per instruction Operand, for Unsigned or Signed values. For example, Relative offset Operand values would typically be configured as Signed values.

- Configurable, per instruction Operand, for rendering each Operand value in either Hex or Decimal format.

- Supports up to 32,767 unique instruction definitions per CPU definition file.

## CPU ISA's currently defined (Complete), or in progress (Incomplete)

- Motorola MC6800 8-bit CPU (Dasm6800.csv) - Complete
- MOS Technology 6502 8-bit CPU (Dasm6502.csv) - Complete
- Western Design Center (WDC) 65C02 8-bit CPU (Dasm65C02.csv) - Complete
- Western Design Center (WDC) W65C02S 8-bit CPU (DasmW65C02S.csv) - Complete
- Western Design Center (WDC) 65C816 8/16-bit CPU (Dasm65C816.csv) - Complete
- Motorola MC6809 8/16-bit CPU (Dasm6809.csv) - Complete
- Sony SPC700 8-bit CPU - Complete (contributed by exodustx0)
- Intel 8085(A) 8-bit CPU - Complete (contributed by schnepe2)

All the Complete definitions have been carefully checked, however if you identify any coding errors please raise an issue or cummunicate with the contributer, so these can be corrected.

Of Note:
- Currently only the W65C02S, 65C816 and SPC700 definitions include instructions having two Operands.
- Currently the MC6809 is the most complex definition, due to it's comprehensive addressing modes and extended multiple-byte opcodes. The MC6809 definition includes 5,530 unique instructions. For comparison the MC6800 has only 197 unique instruction definitions, or the simplest MOS 6502 which requires only 151 unique instruction definitions.

## Source

The fully commented source code is available in the src folder (for those interested).  Note that the source code is not required for using this HxD DataInsepctor Plugin (the required compiled .dll is in the Win64 or Win32 folder), nor is it required for adding your own .csv CPU definitions (if you do create an additional CPU defintion file, please share it!).

The source code was compiled with Delphi 10.3 Community Edition. The Community Edition is available free for non-profit use, however please refer to the Embarcadero website for their full license terms and to obtain the Delphi IDE.

## License

HxD Plugin Framework is Copyright (C) 2019-2021 Maël Hörz. The plugin framework is licensed under the MPL.

This Disassembly Plugin is Copyright (C) 2021 DigicoolThings (Digicool Things), and distributed as per the MPL Larger Work definition and [licensed under the Apache License 2.0](LICENSE)

## Contact

For bugs and CPU definition discussion, please use the issue tracker on GitHub.

There is also discussion on the forum: https://forum.mh-nexus.de
