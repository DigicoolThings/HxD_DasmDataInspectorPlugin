{-------------------------------------------------------------------------------
// Copyright 2021 DigicoolThings (Digicool Things)
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
// Latest version can be found here: https://github.com/DigicoolThings
-------------------------------------------------------------------------------}

unit CpuDefinition;

interface

uses
  Classes, SysUtils, StrUtils;

type
  TCpuDefinition = class
    Private
      type
        PInt8 = ^Int8;
        PInt16 = ^Int16;
        PInt32 = ^Int32;
        PInt64 = ^Int64;

        PUInt8 = ^UInt8;
        PUInt16 = ^UInt16;
        PUInt32 = ^UInt32;
        PUInt64 = ^UInt64;

        TEndian = (LittleEndian, BigEndian);
        TOperandRender = (OperandHex, OperandDec);
        TOperandType = (OperandSigned, OperandUnsigned);
        TLogLevel = (LogINF, LogDBG);

        TOpcodeDefinition = record
          OpcodeBytes: TBytes;
          OperandBytes: TBytes;
          FirstOperandMask: TBytes;
          FirstOperandHexDec: TOperandRender;
          FirstOperandSignedUnsigned: TOperandType;
          SecondOperandMask: TBytes;
          SecondOperandHexDec: TOperandRender;
          SecondOperandSignedUnsigned: TOperandType;
          AssemblyString: string;
        end;

    Private
      _OpcodeDefinitions: Array of TOpcodeDefinition;
      _OpcodeFirstByteIndex: Array[0..$FF] of Int16;
      _LogFile: TextFile;
      _LogFilePath: string;
      _LogEnabled: boolean;
      _LogLevel: TLogLevel;
      _LogAssigned: boolean;
      _OperandEndianness: TEndian;
      _FirstOperandWildcard: string;
      _SecondOperandWildcard: string;

      function _OpcodeCount: Int16;
      function _GetOperandEndianness: string;
    Public
      property OpcodeCount: Int16 read _OpcodeCount;
      property OperandEndianness: string read _GetOperandEndianness;
      property FirstOperandWildcard: string read _FirstOperandWildcard;
      property SecondOperandWildcard: string read _SecondOperandWildcard;

      constructor Create(DefinitionFile, OperandEndianness: string;
                         FirstOperandWildcard: string = '?'; SecondOperandWildcard: string = '^'; LogLevel: string = ''; LogPath: String = '');

      procedure ReverseByteOrder(var Values: TBytes);
      procedure WriteLog(LogString: string; LogBytes: TBytes = nil; FlushLog: boolean = true);

      function DisassembleInstruction(ByteSequence: TBytes; out AssemblyString: string; out DisassembledByteCount: integer): boolean;
  end;


implementation

{-------------------------------------------------------------------------------
 The following RTLVersion compiler directive was added by Maël Hörz to allow
 support for compilation with Delphi XE6 and prior.
 Adds simplified support for TBytes Insert/Delete missing in earlier Delphi.
-------------------------------------------------------------------------------}
{$IF RTLVersion <= 27.0}
procedure Delete(var S: string; Index, Count: Integer); overload; inline;
begin
  System.Delete(S, Index, Count);
end;

procedure Delete(var Dest: TBytes; Index, Count: NativeInt); overload;
var
  L, N: NativeInt;
  S, D: Pointer;
begin
  if Dest <> nil then
  begin
    L := Length(Dest);
    if (Index >= 0) and (Index < L) and (Count > 0) then
    begin
      N := L - Index - Count;
      if N < 0 then
        N := 0;

      D := @PByte(Dest)[Index];
      S := @PByte(Dest)[(L - N)];
      Move(S^, D^, N);
      SetLength(Dest, Index + N);
    end;
  end;
end;

procedure Insert(const Source: Byte; var Dest: TBytes; Index: NativeInt);
const
  SourceLen = 1;
var
  DestLen, NewLen: NativeInt;
begin
  if Dest = nil then
    DestLen := 0
  else
    DestLen := Length(Dest);
  if Index < 0 then
    Index := 0
  else
  begin
    if Index > DestLen then
      Index := DestLen;
  end;

  NewLen := DestLen + SourceLen;
  if NewLen < 0 then   // overflow check
    Error(reIntOverflow);
  SetLength(Dest, NewLen);
  if Index < DestLen then
  begin
    Move(PByte(Dest)[Index], PByte(Dest)[(Index + SourceLen)],
      (DestLen - Index));
  end;
  PByte(Dest)[Index] := PByte(@Source)^
end;
{$ENDIF}

{ TCpuDefinition }

constructor TCpuDefinition.Create(DefinitionFile, OperandEndianness: string; FirstOperandWildcard: string = '?'; SecondOperandWildcard: string = '^'; LogLevel: string = ''; LogPath: String = '');
var Lp, ImportedOpcodeCount, DelimPos: Word;
    TempOpcode, DebugString: string;
    TempHexString: string;
    OpcodeList: TStringList;
    TempOpcodeDefinition: TOpcodeDefinition;

begin
  if (AnsiLowerCase(LogLevel) = 'dbg') or (AnsiLowerCase(LogLevel) = 'debug')
    then _LogLevel := LogDBG
    else _LogLevel := LogINF;
  _LogEnabled := ((Length(LogLevel) > 0) and (LogLevel[1] <> '0'));
  _LogAssigned := False;
  if AnsiLowerCase(LeftStr(OperandEndianness,3)) = 'big'
    then _OperandEndianness := BigEndian
    else _OperandEndianness := LittleEndian;
  if length(FirstOperandWildcard) > 0 then _FirstOperandWildcard := FirstOperandWildcard
                                      else _FirstOperandWildcard := '?';
  if length(SecondOperandWildcard) > 0 then _SecondOperandWildcard := SecondOperandWildcard
                                      else _SecondOperandWildcard := '^';
  _LogFilePath := ChangeFileExt(ExtractFileName(DefinitionFile),'.log');
  if length(LogPath) > 0 then
    _LogFilePath := IncludeTrailingPathDelimiter(LogPath)+_LogFilePath;
  if _LogEnabled then DeleteFile(_LogFilePath);

  for Lp := 0 to $FF do _OpcodeFirstByteIndex[Lp] := -1;

  ImportedOpcodeCount:=0;
  OpcodeList:= TStringList.Create;
  try
    try

      OpcodeList.CaseSensitive:=False;
      OpcodeList.Duplicates:=dupIgnore;
      OpcodeList.LoadFromFile(DefinitionFile);
      if OpcodeList.Count > 0 then
      begin
{-------------------------------------------------------------------------------
 Before sorting the string (to be in Opcode sequence) we need to trim any
 leading spaces.
-------------------------------------------------------------------------------}
        for Lp := 0 to OpcodeList.Count-1 do
        begin
         OpcodeList[Lp] := trim(OpcodeList[Lp]);
        end;
{-------------------------------------------------------------------------------
 We also want to remove any CSV header line that may (optionally) be present.
-------------------------------------------------------------------------------}
        if AnsiLowerCase(LeftStr(OpcodeList[0],6)) = 'opcode' then OpcodeList.Delete(0);
{-------------------------------------------------------------------------------
 Now Sort the loaded CPU Opcode defintions into Hex OpcodeBytes sequence.
-------------------------------------------------------------------------------}
        OpcodeList.Sort;
        while Length(OpcodeList[0]) = 0 do OpcodeList.Delete(0);
      end;
      SetLength(_OpcodeDefinitions,OpcodeList.Count);
      for Lp := 0 to OpcodeList.Count-1 do
      begin
{-------------------------------------------------------------------------------
 Process each CSV string
-------------------------------------------------------------------------------}
        TempOpcode:=OpcodeList[Lp];

        if _LogEnabled then WriteLog('[Source Definition '+IntToStr(Lp+1)+'] '+TempOpcode);

{-------------------------------------------------------------------------------
 First process the OpcodeBytes column. Minimum length is 1 Byte (2 hex chars).
 Purge any spaces, ensure an even number of Hex pairs, and no failed byte
 conversions.
-------------------------------------------------------------------------------}
        DelimPos := Pos(',', TempOpcode);
        if (DelimPos > 0) then
        begin
          TempHexString:=AnsiLowerCase(StringReplace(Copy(TempOpcode,1,DelimPos-1),' ','',[rfReplaceAll]));
          Delete(TempOpcode,1,DelimPos);
          if (DelimPos > 1) and not(Odd(Length(TempHexString))) then
          begin
            SetLength(TempOpcodeDefinition.OpcodeBytes,Length(TempHexString) div 2);
            if (HexToBin(PChar(TempHexString),TempOpcodeDefinition.OpcodeBytes,Length(TempHexString) div 2) = Length(TempHexString) div 2) then
            begin
{-------------------------------------------------------------------------------
 Next, process the OperandBytes column. Minimum Length is 0 (zero) Bytes
 (eg. 1 byte inherent addressing Opcodes).
 Purge any spaces, ensure an even number of Hex pairs, and no failed byte
 conversions.
-------------------------------------------------------------------------------}
              DelimPos := Pos(',', TempOpcode);
              if (DelimPos > 0) then
              begin
                TempHexString:=AnsiLowerCase(StringReplace(Copy(TempOpcode,1,DelimPos-1),' ','',[rfReplaceAll]));
                Delete(TempOpcode,1,DelimPos);
                if not(Odd(Length(TempHexString))) then
                begin
                  SetLength(TempOpcodeDefinition.OperandBytes,Length(TempHexString) div 2);
                  if (HexToBin(PChar(TempHexString),TempOpcodeDefinition.OperandBytes,Length(TempHexString) div 2) = Length(TempHexString) div 2) then
                  begin

{-------------------------------------------------------------------------------
 Next, process the FirstOperandMask column.
 Maximum length is the length of the OperandBytes.
 Result is to be same length as OperandBytes via left (most significant byte)
 zero padding, if required.
 Purge any spaces, ensure an even number of Hex pairs, and no failed byte
 conversions.
-------------------------------------------------------------------------------}
                    DelimPos := Pos(',', TempOpcode);
                    if (DelimPos > 0) then
                    begin
                      TempHexString:=AnsiLowerCase(StringReplace(Copy(TempOpcode,1,DelimPos-1),' ','',[rfReplaceAll]));
                      Delete(TempOpcode,1,DelimPos);
                      if ((Length(TempHexString) div 2) <= Length(TempOpcodeDefinition.OperandBytes)) and not(Odd(Length(TempHexString))) then
                      begin
                        SetLength(TempOpcodeDefinition.FirstOperandMask,Length(TempOpcodeDefinition.OperandBytes));
{-------------------------------------------------------------------------------
 If required now pad to same length as OperandBytes via most significant byte
 zero padding.
 if Operand is Big Endian then we need to prefix the zero bytes.
 if Operand is Little Endian then we need to suffix the zero bytes.
-------------------------------------------------------------------------------}
                        if _OperandEndianness = BigEndian
                          then while (Length(TempHexString) div 2) < Length(TempOpcodeDefinition.OperandBytes) do TempHexString:='00'+TempHexString
                          else while (Length(TempHexString) div 2) < Length(TempOpcodeDefinition.OperandBytes) do TempHexString:=TempHexString+'00';

                        if (HexToBin(PChar(TempHexString),TempOpcodeDefinition.FirstOperandMask,Length(TempHexString) div 2) = Length(TempHexString) div 2) then
                        begin
{-------------------------------------------------------------------------------
 Next, process the FirstOperandHexDec column. Valid CSV field values are blank,
 D/d (Decimal), or H/h (Hex).
 Purge any spaces. A blank value is defaulted to h (Hex).
 In many cases a blank value will simply be because the value is Don't Care,
 (eg. There are no OperandBytes or no non-zero FirstOperandMask)
-------------------------------------------------------------------------------}
                          DelimPos := Pos(',', TempOpcode);
                          if (DelimPos > 0) then
                          begin
                            TempHexString:=AnsiLowerCase(StringReplace(Copy(TempOpcode,1,DelimPos-1),' ','',[rfReplaceAll]));
                            Delete(TempOpcode,1,DelimPos);
                            if (Length(TempHexString) = 0) then TempHexString := 'h';
                            if CharInSet(TempHexString[1], ['h','d']) then
                            begin
                              if TempHexString[1] = 'h' then TempOpcodeDefinition.FirstOperandHexDec := OperandHex
                                                        else TempOpcodeDefinition.FirstOperandHexDec := OperandDec;
{-------------------------------------------------------------------------------
 Next, process the FirstOperandSignedUnsigned column.
 Valid CSV field values are blank, S/s (Signed), or U/u (Unsigned).
 Purge any spaces. A blank value is defaulted to u (Unsigned).
 In many cases a blank value will simply be because the value is Don't Care,
 (eg. There are no OperandBytes or no non-zero FirstOperandMask)
-------------------------------------------------------------------------------}
                              DelimPos := Pos(',', TempOpcode);
                              if (DelimPos > 0) then
                              begin
                                TempHexString:=AnsiLowerCase(StringReplace(Copy(TempOpcode,1,DelimPos-1),' ','',[rfReplaceAll]));
                                Delete(TempOpcode,1,DelimPos);
                                if (Length(TempHexString) = 0) then TempHexString := 'u';
                                if CharInSet(TempHexString[1], ['s','u']) then
                                begin
                                  if TempHexString[1] = 'u' then TempOpcodeDefinition.FirstOperandSignedUnsigned := OperandUnsigned
                                                            else TempOpcodeDefinition.FirstOperandSignedUnsigned := OperandSigned;

{-------------------------------------------------------------------------------
 Next, process the SecondOperandMask column.
 Maximum length is the length of the OperandBytes.
 Result is to be same length as OperandBytes via most significant byte
 zero padding, if required.
 Purge any spaces, ensure an even number of Hex pairs, and no failed byte
 conversions.
-------------------------------------------------------------------------------}
                                  DelimPos := Pos(',', TempOpcode);
                                  if (DelimPos > 0) then
                                  begin
                                    TempHexString:=AnsiLowerCase(StringReplace(Copy(TempOpcode,1,DelimPos-1),' ','',[rfReplaceAll]));
                                    Delete(TempOpcode,1,DelimPos);
                                    if ((Length(TempHexString) div 2) <= Length(TempOpcodeDefinition.OperandBytes)) and not(Odd(Length(TempHexString))) then
                                    begin
                                      SetLength(TempOpcodeDefinition.SecondOperandMask,Length(TempOpcodeDefinition.OperandBytes));
{-------------------------------------------------------------------------------
 If required now pad to same length as OperandBytes via most significant byte
 zero padding.
 if Operand is Big Endian then we need to prefix the zero bytes.
 if Operand is Little Endian then we need to suffix the zero bytes.
-------------------------------------------------------------------------------}
                                      if _OperandEndianness = BigEndian
                                        then while (Length(TempHexString) div 2) < Length(TempOpcodeDefinition.OperandBytes) do TempHexString:='00'+TempHexString
                                        else while (Length(TempHexString) div 2) < Length(TempOpcodeDefinition.OperandBytes) do TempHexString:=TempHexString+'00';

                                      if (HexToBin(PChar(TempHexString),TempOpcodeDefinition.SecondOperandMask,Length(TempHexString) div 2) = Length(TempHexString) div 2) then
                                      begin
{-------------------------------------------------------------------------------
 Next, process the SecondOperandHexDec column. Valid CSV field values are blank,
 D/d (Decimal), or H/h (Hex).
 Purge any spaces. A blank value is defaulted to h (Hex).
 In many cases a blank value will simply be because the value is Don't Care,
 (eg. There are no OperandBytes or no non-zero SecondOperandMask)
-------------------------------------------------------------------------------}
                                        DelimPos := Pos(',', TempOpcode);
                                        if (DelimPos > 0) then
                                        begin
                                          TempHexString:=AnsiLowerCase(StringReplace(Copy(TempOpcode,1,DelimPos-1),' ','',[rfReplaceAll]));
                                          Delete(TempOpcode,1,DelimPos);
                                          if (Length(TempHexString) = 0) then TempHexString := 'h';
                                          if CharInSet(TempHexString[1], ['h','d']) then
                                          begin
                                            if TempHexString[1] = 'h' then TempOpcodeDefinition.SecondOperandHexDec := OperandHex
                                                                      else TempOpcodeDefinition.SecondOperandHexDec := OperandDec;
{-------------------------------------------------------------------------------
 Next, process the SecondOperandSignedUnsigned column.
 Valid CSV field values are blank, S/s (Signed), or U/u (Unsigned).
 Purge any spaces. A blank value is defaulted to u (Unsigned).
 In many cases a blank value will simply be because the value is Don't Care,
 (eg. There are no OperandBytes or no non-zero SecondOperandMask)
-------------------------------------------------------------------------------}
                                            DelimPos := Pos(',', TempOpcode);
                                            if (DelimPos > 0) then
                                            begin
                                              TempHexString:=AnsiLowerCase(StringReplace(Copy(TempOpcode,1,DelimPos-1),' ','',[rfReplaceAll]));
                                              Delete(TempOpcode,1,DelimPos);
                                              if (Length(TempHexString) = 0) then TempHexString := 'u';
                                              if CharInSet(TempHexString[1], ['s','u']) then
                                              begin
                                                if TempHexString[1] = 'u' then TempOpcodeDefinition.SecondOperandSignedUnsigned := OperandUnsigned
                                                                          else TempOpcodeDefinition.SecondOperandSignedUnsigned := OperandSigned;

{-------------------------------------------------------------------------------
 Finally process the AssemblyString column.
 Purge any double quote chars. As a double quote char is not typical in
 Assembly code we can safely purge all double quotes.
 Valid resulting field is a string of 1 or more chars.
-------------------------------------------------------------------------------}
                                                TempOpcode:=StringReplace(TempOpcode,'"','',[rfReplaceAll]);
                                                if (Length(TempOpcode) > 0) then
                                                begin
                                                  TempOpcodeDefinition.AssemblyString:=TempOpcode;

                                                  _OpcodeDefinitions[ImportedOpcodeCount]:=TempOpcodeDefinition;
                                                  Inc(ImportedOpcodeCount);

                                                  if (_OpcodeFirstByteIndex[TempOpcodeDefinition.OpcodeBytes[0]] < 0) then
                                                  begin
                                                    _OpcodeFirstByteIndex[TempOpcodeDefinition.OpcodeBytes[0]] := ImportedOpcodeCount - 1;
                                                    if _LogEnabled then
                                                    begin
                                                      SetLength(TempOpcode, 2);
                                                      BinToHex(TempOpcodeDefinition.OpcodeBytes,PWideChar(TempOpcode),1);
                                                      DebugString := TempOpcode;
                                                      WriteLog('[Parsed Definition '+IntToStr(ImportedOpcodeCount)+'] First entry for Opcodes commencing '+DebugString);
                                                    end;
                                                  end;

{-------------------------------------------------------------------------------
 The following code block simply compiles the resulting parsed record values
 for writing to the log.
 Although WriteLog will only write to the log if LogEnabled = True, we also
 perform the test here, simply to avoid wasting time building the log entry
 if it is not actually needed.
-------------------------------------------------------------------------------}
                                                  if _LogEnabled then
                                                  begin
                                                    SetLength(TempOpcode, Length(TempOpcodeDefinition.OpcodeBytes) * 2);
                                                    BinToHex(TempOpcodeDefinition.OpcodeBytes,PWideChar(TempOpcode),Length(TempOpcodeDefinition.OpcodeBytes));
                                                    DebugString := TempOpcode;

                                                    SetLength(TempOpcode, Length(TempOpcodeDefinition.OperandBytes) * 2);
                                                    BinToHex(TempOpcodeDefinition.OperandBytes,PWideChar(TempOpcode),Length(TempOpcodeDefinition.OperandBytes));
                                                    DebugString := DebugString+'|'+TempOpcode;

                                                    SetLength(TempOpcode, Length(TempOpcodeDefinition.FirstOperandMask) * 2);
                                                    BinToHex(TempOpcodeDefinition.FirstOperandMask,PWideChar(TempOpcode),Length(TempOpcodeDefinition.FirstOperandMask));
                                                    DebugString := DebugString+'|'+TempOpcode;
                                                    case TempOpcodeDefinition.FirstOperandHexDec of
                                                      OperandHex: DebugString := DebugString+'|Hex';
                                                      OperandDec: DebugString := DebugString+'|Dec';
                                                    end;
                                                    case TempOpcodeDefinition.FirstOperandSignedUnsigned of
                                                      OperandSigned: DebugString := DebugString+'|Signed';
                                                      OperandUnsigned: DebugString := DebugString+'|Unsigned';
                                                    end;

                                                    SetLength(TempOpcode, Length(TempOpcodeDefinition.SecondOperandMask) * 2);
                                                    BinToHex(TempOpcodeDefinition.SecondOperandMask,PWideChar(TempOpcode),Length(TempOpcodeDefinition.SecondOperandMask));
                                                    DebugString := DebugString+'|'+TempOpcode;
                                                    case TempOpcodeDefinition.SecondOperandHexDec of
                                                      OperandHex: DebugString := DebugString+'|Hex';
                                                      OperandDec: DebugString := DebugString+'|Dec';
                                                    end;
                                                    case TempOpcodeDefinition.SecondOperandSignedUnsigned of
                                                      OperandSigned: DebugString := DebugString+'|Signed';
                                                      OperandUnsigned: DebugString := DebugString+'|Unsigned';
                                                    end;

                                                    DebugString := DebugString+'|'+TempOpcodeDefinition.AssemblyString;

                                                    WriteLog('[Parsed Definition '+IntToStr(ImportedOpcodeCount)+'] '+DebugString);
                                                  end;

                                                end
                                                else WriteLog('ERROR: No AssemblyString value found');

                                              end
                                              else WriteLog('ERROR: Invalid SecondOperandSignedUnsigned value ('+TempHexString[1]+')');
                                            end
                                            else WriteLog('ERROR: No SecondOperandSignedUnsigned delimiter found ('+TempOpcode+')');
                                          end
                                          else WriteLog('ERROR: Invalid SecondOperandHexDec value ('+TempHexString[1]+')');
                                        end
                                        else WriteLog('ERROR: No SecondOperandHexDec delimiter found ('+TempOpcode+')');
                                      end
                                      else WriteLog('ERROR: Invalid SecondOperandMask hex string ('+TempHexString+')');
                                    end
                                    else WriteLog('ERROR: Odd SecondOperandMask length or Mask is longer than OperandBytes ('+TempHexString+')');
                                  end
                                  else WriteLog('ERROR: No SecondOperandMask delimiter found ('+TempOpcode+')');

                                end
                                else WriteLog('ERROR: Invalid FirstOperandSignedUnsigned value ('+TempHexString[1]+')');
                              end
                              else WriteLog('ERROR: No FirstOperandSignedUnsigned delimiter found ('+TempOpcode+')');
                            end
                            else WriteLog('ERROR: Invalid FirstOperandHexDec value ('+TempHexString[1]+')');
                          end
                          else WriteLog('ERROR: No FirstOperandHexDec delimiter found ('+TempOpcode+')');
                        end
                        else WriteLog('ERROR: Invalid FirstOperandMask hex string ('+TempHexString+')');
                      end
                      else WriteLog('ERROR: Odd FirstOperandMask length or Mask is longer than OperandBytes ('+TempHexString+')');
                    end
                    else WriteLog('ERROR: No FirstOperandMask delimiter found ('+TempOpcode+')');

                  end
                  else WriteLog('ERROR: Invalid OperandBytes hex string ('+TempHexString+')');
                end
                else WriteLog('ERROR: Odd OperandBytes length ('+TempHexString+')');
              end
              else WriteLog('ERROR: No OperandBytes delimiter found ('+TempOpcode+')');
            end
            else WriteLog('ERROR: Invalid OpcodeBytes hex string ('+TempHexString+')');
          end
          else WriteLog('ERROR: Odd OpcodeBytes length or no OpcodeBytes ('+TempHexString+')');
        end
        else WriteLog('ERROR: No OpcodeBytes delimiter found ('+TempOpcode+')');
      end;
      SetLength(_OpcodeDefinitions,ImportedOpcodeCount);

    except
    end;
  finally
    OpcodeList.Free;
  end;
end;

procedure TCpuDefinition.ReverseByteOrder(var Values: TBytes);
{-------------------------------------------------------------------------------
 Reverse the Byte order of an array of bytes.
 Intended for generalised reversal of any Byte sequence.
 eg. For Big Endian vs Little Endian system byte sequences.
-------------------------------------------------------------------------------}
var
  Lp: Int16;
  Value: Byte;
begin
  for Lp := 0 to High(Values) div 2 do
  begin
    Value := Values[Lp];
    Values[Lp] := Values[High(Values) - Lp];
    Values[High(Values) - Lp] := Value;
  end;
end;

function TCpuDefinition._OpcodeCount: Int16;
begin
  try
    Result:=Length(_OpcodeDefinitions);
  except
    Result:=0
  end;
end;

function TCpuDefinition._GetOperandEndianness: string;
begin
  if _OperandEndianness = BigEndian
    then Result := 'Big'
    else Result := 'Little';
end;

procedure TCpuDefinition.WriteLog(LogString: string; LogBytes: TBytes = nil; FlushLog: boolean = true);
{-------------------------------------------------------------------------------
 A simplified / cut-down WriteLog procedure from my own log handling unit,
 which I've just embedded within the CpuDefintion class for the simple logging
 requirement. The Log DisplayDateTimeFormat simply hardwired as a universally
 understood format.
-------------------------------------------------------------------------------}
const
  DisplayDateTimeFormat = 'dd-MMM-yyyy hh:mm:ss';
var
  TempOutputStr: string;
begin
  if _LogEnabled then
  begin
    try
      if (not _LogAssigned) then
      begin
        AssignFile(_LogFile, _LogFilePath);
        {$I-}
        Append(_LogFile);
        {$I+}
        if (IOResult <> 0) then ReWrite(_LogFile);

        _LogAssigned:=True;
      end;

      TempOutputStr := FormatDateTime(DisplayDateTimeFormat,Now)+' '+LogString;
      TempOutputStr := '';
      if (Length(LogBytes) > 0) then
      begin
        SetLength(TempOutputStr, Length(LogBytes) * 2);
        BinToHex(LogBytes,PWideChar(TempOutputStr),Length(LogBytes));
      end;

      if length(TempOutputStr) > 0
        then Writeln(_LogFile, FormatDateTime(DisplayDateTimeFormat,Now)+' '+LogString+' ['+TempOutputStr+']')
        else Writeln(_LogFile, FormatDateTime(DisplayDateTimeFormat,Now)+' '+LogString);

      if FlushLog then Flush(_LogFile);

      CloseFile(_LogFile);
      _LogAssigned:=False;
    except
    end;
  end;
end;

function TCpuDefinition.DisassembleInstruction(ByteSequence: TBytes; out AssemblyString: string; out DisassembledByteCount: integer): boolean;
{-------------------------------------------------------------------------------
 This function attempts to Disassemble the input Byte sequence (ByteSequence),
 into a single Assembly instruction (AssemblyString).
 The count of the Bytes used in the instruction Disassembly is returned as
 DisassembledByteCount.
 The return value is True if successful / False if unable to Disassemble.
-------------------------------------------------------------------------------}
var
  ByteIndex, ByteOffset, OpcodeBytesLength, OperandBytesLength: Int16;
  MatchFound, OpcodeMatch, OperandMatch: boolean;
  TempBytes: TBytes;
  InvertedOperandMask: TBytes;
  FirstOperandMask, FirstOperandBytes: TBytes;
  FirstOperandStr: string;
  FirstOperandLength: Int16;
  SecondOperandMask, SecondOperandBytes: TBytes;
  SecondOperandStr: string;
  SecondOperandLength: Int16;
  isFirstOperandMsbSet, isSecondOperandMsbSet: boolean;
  Carry, MsbMask: byte;
  Lp: Integer;

  function GetOperandStr(var prmOperandHexDec: TOperandRender; var prmOperandSignedUnsigned: TOperandType; var prmOperandLength: Int16; var prmOperandBytes: TBytes): string;
{-------------------------------------------------------------------------------
 Return the appropriate string representation of prmOperandBytes, for rendering.
 If Hex format then we need to seperately handle Signed vs Unsigned values.
 For Signed values we need to deal with -ve value rendering, using a -$ format.
 For Unsigned values (and +ve Signed values) we just need to convert to a Hex
 string and prefix '$' (to signify a Hex value).
 prmOperandBytes must be an array of 1,2,4 or 8 bytes (ie. 8,16,32 or 64 bits).
 prmOperandLength specifies the desired byte length to return in the string.
 prmOperandLength must be <= Length(prmOperandBytes)
 *******************************************************************************
 NOTE: Code size could have been optimised, by first normalising to a consistant
 64 bit value (8 byte array). ie. Case statements would then not be required.
 However, the resulting smaller code size would also add the overhead of always
 otherwise needlessly padding 1,2,4 byte values out to 8 bytes.
 Therefore performance was prioritised over code size.
 *******************************************************************************
-------------------------------------------------------------------------------}
  begin
    Result:='';
    if (prmOperandHexDec = OperandHex) then
    begin
{-------------------------------------------------------------------------------
 The following commented-out code was originally used when we simply rendered
 the raw Hex values, irrespective of them being Signed or Unsigned.
 The original assumption was that the viewer would understand that a relative
 reference (for example) of $FF, would equate to -1 (two's complement).
 This was based on my own personal history of manually counting back branch
 relative offsets in hand assembled machine code. ie. FF.. FE.. FD.. etc.
 However Maël (HxD author) pointed out that -ve representation was also
 appropriate for Hex.
//                  ReverseByteOrder(prmOperandBytes);
//                  SetLength(Result, Length(prmOperandBytes) * 2);
//                  BinToHex(prmOperandBytes,PWideChar(Result),Length(prmOperandBytes));
//                  FirstOperandStr := '$'+Result;
-------------------------------------------------------------------------------}
{
      if (prmOperandSignedUnsigned = OperandSigned) then
      begin
        case Length(prmOperandBytes) of
          1: if (PInt8(@prmOperandBytes[0])^ < 0) then Result := '-$' + IntToHex(-PInt8(@prmOperandBytes[0])^,2)
                                                else Result := '$' + IntToHex(PInt8(@prmOperandBytes[0])^);
          2: if (PInt16(@prmOperandBytes[0])^ < 0) then Result := '-$' + IntToHex(-PInt16(@prmOperandBytes[0])^,4)
                                                 else Result := '$' + IntToHex(PInt16(@prmOperandBytes[0])^);
          4: if (PInt32(@prmOperandBytes[0])^ < 0) then Result := '-$' + IntToHex(-Pint32(@prmOperandBytes[0])^,8)
                                                 else Result := '$' + IntToHex(Pint32(@prmOperandBytes[0])^);
          8: if (PInt64(@prmOperandBytes[0])^ < 0) then Result := '-$' + IntToHex(-Pint64(@prmOperandBytes[0])^,16)
                                                 else Result := '$' + IntToHex(Pint64(@prmOperandBytes[0])^);
        end;
      end
      else
      begin
        case Length(prmOperandBytes) of
          1: Result := '$' + IntToHex(PUInt8(@prmOperandBytes[0])^);
          2: Result := '$' + IntToHex(PUInt16(@prmOperandBytes[0])^);
          4: Result := '$' + IntToHex(PUint32(@prmOperandBytes[0])^);
          8: Result := '$' + IntToHex(PUint64(@prmOperandBytes[0])^);
        end;
      end;
}
      if (prmOperandSignedUnsigned = OperandSigned) then
      begin
        case Length(prmOperandBytes) of
          1: if (PInt8(@prmOperandBytes[0])^ < 0) then Result := '-$' + IntToHex(-PInt8(@prmOperandBytes[0])^,prmOperandLength*2)
                                                else Result := '$' + IntToHex(PInt8(@prmOperandBytes[0])^,prmOperandLength*2);
          2: if (PInt16(@prmOperandBytes[0])^ < 0) then Result := '-$' + IntToHex(-PInt16(@prmOperandBytes[0])^,prmOperandLength*2)
                                                 else Result := '$' + IntToHex(PInt16(@prmOperandBytes[0])^,prmOperandLength*2);
          4: if (PInt32(@prmOperandBytes[0])^ < 0) then Result := '-$' + IntToHex(-Pint32(@prmOperandBytes[0])^,prmOperandLength*2)
                                                 else Result := '$' + IntToHex(Pint32(@prmOperandBytes[0])^,prmOperandLength*2);
          8: if (PInt64(@prmOperandBytes[0])^ < 0) then Result := '-$' + IntToHex(-Pint64(@prmOperandBytes[0])^,prmOperandLength*2)
                                                 else Result := '$' + IntToHex(Pint64(@prmOperandBytes[0])^,prmOperandLength*2);
        end;
      end
      else
      begin
        case Length(prmOperandBytes) of
          1: Result := '$' + IntToHex(PUInt8(@prmOperandBytes[0])^,prmOperandLength*2);
          2: Result := '$' + IntToHex(PUInt16(@prmOperandBytes[0])^,prmOperandLength*2);
          4: Result := '$' + IntToHex(PUint32(@prmOperandBytes[0])^,prmOperandLength*2);
          8: Result := '$' + IntToHex(PUint64(@prmOperandBytes[0])^,prmOperandLength*2);
        end;
      end;

    end
    else
    begin
{-------------------------------------------------------------------------------
 Otherwise, for Dec format we need to convert, based on the Operand being
 either a Signed or Unsigned value.
-------------------------------------------------------------------------------}
      if (prmOperandSignedUnsigned = OperandSigned) then
      begin
        case Length(prmOperandBytes) of
          1: Result := IntToStr(PInt8(@prmOperandBytes[0])^);
          2: Result := IntToStr(PInt16(@prmOperandBytes[0])^);
          4: Result := IntToStr(Pint32(@prmOperandBytes[0])^);
          8: Result := IntToStr(Pint64(@prmOperandBytes[0])^);
        end;
      end
      else
      begin
        case Length(prmOperandBytes) of
          1: Result := UIntToStr(PUInt8(@prmOperandBytes[0])^);
          2: Result := UIntToStr(PUInt16(@prmOperandBytes[0])^);
          4: Result := UIntToStr(PUint32(@prmOperandBytes[0])^);
          8: Result := UIntToStr(PUint64(@prmOperandBytes[0])^);
        end;
      end;
    end;
  end;

(*
  function GetOperandStr(var prmOperandHexDec: TOperandRender; var prmOperandSignedUnsigned: TOperandType; var prmOperandLength: Int16; var prmOperandBytes: TBytes): string;
{-------------------------------------------------------------------------------
 Return the appropriate string representation of prmOperandBytes, for rendering.
 If Hex format then we need to seperately handle Signed vs Unsigned values.
 For Signed values we need to deal with -ve value rendering, using a -$ format.
 For Unsigned values (and +ve Signed values) we just need to convert to a Hex
 string and prefix '$' (to signify a Hex value).
 prmOperandBytes must be an array of 8 bytes (ie. a 64 bit value).
 prmOperandLength specifies the desired byte length to return in the string.
 prmOperandLength must be <= Length(prmOperandBytes)
 *******************************************************************************
 NOTE: This is the version that optimises code size by requiring a consistant
 64 bit value (8 byte array). ie. Case statements not required.
 However, this resulting smaller code size does add the overhead of always
 needlessly padding 1,2,4 byte values out to 8 bytes.
 ie. Codes size is optimised at the cost of performance.
 *******************************************************************************
 ------------------------------------------------------------------------------}
  begin
    Result:='';
    if (prmOperandHexDec = OperandHex) then
    begin
      if (prmOperandSignedUnsigned = OperandUnsigned) then Result := '$' + IntToHex(PUint64(@prmOperandBytes[0])^,prmOperandLength*2)
      else if (PInt64(@prmOperandBytes[0])^ < 0) then Result := '-$' + IntToHex(-Pint64(@prmOperandBytes[0])^,prmOperandLength*2)
                                                 else Result := '$' + IntToHex(Pint64(@prmOperandBytes[0])^,prmOperandLength*2);
    end
    else
    begin
{-------------------------------------------------------------------------------
 Otherwise, for Dec format we need to convert, based on the Operand being
 either a Signed or Unsigned value.
-------------------------------------------------------------------------------}
      if (prmOperandSignedUnsigned = OperandUnsigned) then Result := UIntToStr(PUint64(@prmOperandBytes[0])^)
                                                      else Result := IntToStr(Pint64(@prmOperandBytes[0])^);
    end;
  end;
*)

begin
  AssemblyString := '';
  MatchFound := False;
  ByteIndex := _OpcodeFirstByteIndex[ByteSequence[0]];
  if (ByteIndex >= 0) then
  begin
    while (not MatchFound)
      and (ByteIndex < OpcodeCount)
      and (ByteSequence[0] = _OpcodeDefinitions[ByteIndex].OpcodeBytes[0]) do
    begin
      OpcodeBytesLength := Length(_OpcodeDefinitions[ByteIndex].OpcodeBytes);
      OperandBytesLength := Length(_OpcodeDefinitions[ByteIndex].OperandBytes);
{-------------------------------------------------------------------------------
 First check that the ByteSequence is long enough to match this instruction.
 ie. The ByteSequence is at least as long as the Opcode + Operand length.
-------------------------------------------------------------------------------}
      if (Length(ByteSequence) >= (OpcodeBytesLength + OperandBytesLength)) then
      begin
        ByteOffset := 1;
        OpcodeMatch := True;
        while (OpcodeMatch and (ByteOffset < OpcodeBytesLength)) do
        begin
          if (ByteSequence[ByteOffset] <> _OpcodeDefinitions[ByteIndex].OpcodeBytes[ByteOffset]) then
            OpcodeMatch := False;
          inc(ByteOffset);
        end;
        if OpcodeMatch then
        begin
          if (OperandBytesLength = 0) then
          begin
{-------------------------------------------------------------------------------
 We have the case where there is no Operand to match, so we have a MatchFound
 based on an Opcode only instruction (eg. Inherent Adressing).
-------------------------------------------------------------------------------}
            MatchFound := True;
            DisassembledByteCount := OpcodeBytesLength;
            AssemblyString := _OpcodeDefinitions[ByteIndex].AssemblyString;
          end
          else
          begin
{-------------------------------------------------------------------------------
 We have an Operand to process, so let's first establish a local copy of the
 FirstOperandMask and the SecondOperandMask for subsequent processing.
-------------------------------------------------------------------------------}
            FirstOperandMask := Copy(_OpcodeDefinitions[ByteIndex].FirstOperandMask);
            SecondOperandMask := Copy(_OpcodeDefinitions[ByteIndex].SecondOperandMask);
{-------------------------------------------------------------------------------
 Then we use the local InvertedOperandMask to hold an inverted full Operand
 mask based on the combined FirstOperandMask and the SecondOperandMask.
 NOTE: all OperandMask arrays can here be assumed to be of OperandBytesLength.
-------------------------------------------------------------------------------}
            SetLength(InvertedOperandMask,OperandBytesLength);
            for ByteOffset := 0 to High(InvertedOperandMask) do InvertedOperandMask[ByteOffset] := not (FirstOperandMask[ByteOffset] or SecondOperandMask[ByteOffset]);

if (_LogLevel = LogDBG) then
  WriteLog('InvertedOperandMask:', InvertedOperandMask);

{-------------------------------------------------------------------------------
 We can now use the inverted combined Operand masks to check for an instruction
 OperandBytes match.
 NOTE: This assumes that that any bits that are not part of the FirstOperand or
 SecondOperand, are therefore static bits making-up the full instruction match.
-------------------------------------------------------------------------------}
            ByteOffset := 0;
            OperandMatch := True;
            while (OperandMatch and (ByteOffset < OperandBytesLength)) do
            begin
              if (ByteSequence[OpcodeBytesLength + ByteOffset] and InvertedOperandMask[ByteOffset]
                  <> _OpcodeDefinitions[ByteIndex].OperandBytes[ByteOffset] and InvertedOperandMask[ByteOffset]) then
                OperandMatch := False;
              inc(ByteOffset);
            end;
            if OperandMatch then
            begin
{-------------------------------------------------------------------------------
 We have a final instruction match (OpcodeBytes + OperandBytes)! :)
 So we can now update the DisassembledByteCount to the final instruction length.
-------------------------------------------------------------------------------}
              MatchFound := True;
              DisassembledByteCount := OpcodeBytesLength + OperandBytesLength;
              AssemblyString := _OpcodeDefinitions[ByteIndex].AssemblyString;
{-------------------------------------------------------------------------------
 Now extract any OperandBytes, that need to be inserted into the AssemblyString.
 As this is destructive we want to make local copies of the Operand portion of
 the supplied ByteSequence as the working First & Second Operand Bytes for us to
 safely modify / manipulate.
-------------------------------------------------------------------------------}
              FirstOperandBytes := Copy(ByteSequence,OpcodeBytesLength,OperandBytesLength);
              SecondOperandBytes := Copy(ByteSequence,OpcodeBytesLength,OperandBytesLength);

{-------------------------------------------------------------------------------
 Initially we want to normalise the OperandBytes, FirstOperandMask and
 SecondOperandMask bytes into Little Endian byte sequence, so that we can
 perform all FirstOperand processing on the basis that we have Little Endian
 sequence Operand bytes.
 ie. The First byte is the least significant byte!
-------------------------------------------------------------------------------}
              if _OperandEndianness = BigEndian then
              begin
                ReverseByteOrder(FirstOperandBytes);
                ReverseByteOrder(FirstOperandMask);
                ReverseByteOrder(SecondOperandBytes);
                ReverseByteOrder(SecondOperandMask);
              end;

if (_LogLevel = LogDBG) then
begin
  WriteLog('Normalised (LittleEndian) FirstOperandBytes:', FirstOperandBytes);
  WriteLog('Normalised (LittleEndian) FirstOperandMask:', FirstOperandMask);
  WriteLog('Normalised (LittleEndian) SecondOperandBytes:', SecondOperandBytes);
  WriteLog('Normalised (LittleEndian) SecondOperandMask:', SecondOperandMask);
end;

{-------------------------------------------------------------------------------
 We want to strip any trailing zero bits based on the provided bit mask, this
 is to right align the actual Operand portions of the OperandBytes.
 For stripping trailing zero bits we first strip any trailing zero bytes!
 So we purge all trailing (ie. least significant) zero bytes.
 Noting that in Little Endian, trailing (least significant) is the first byte.
-------------------------------------------------------------------------------}
              while (Length(FirstOperandMask) > 0) and (FirstOperandMask[0] = 0) do
              begin
                Delete(FirstOperandMask,0,1);
                Delete(FirstOperandBytes,0,1);
              end;
              while (Length(SecondOperandMask) > 0) and (SecondOperandMask[0] = 0) do
              begin
                Delete(SecondOperandMask,0,1);
                Delete(SecondOperandBytes,0,1);
              end;

if (_LogLevel = LogDBG) then
begin
  WriteLog('FirstOperandBytes (Purged trailing zero bytes):', FirstOperandBytes);
  WriteLog('SecondOperandBytes (Purged trailing zero bytes):', SecondOperandBytes);
end;

{-------------------------------------------------------------------------------
 Only proceed if there was actually a FirstOperand Mask!
 ie. If after purging trailing zero bytes we have deleted all bytes in the mask,
 then obviously there was no mask specified.
 If no FirstOperand mask, then there is no FirstOperand value to be extracted!
 Also, if there's no FirstOperand then we also assume no SecondOperand.
-------------------------------------------------------------------------------}
              if Length(FirstOperandMask) > 0 then
              begin
{-------------------------------------------------------------------------------
 Now purge all trailing zero bits by right bit shifting the bytes arrays.
 Again noting that Little Endian has the least significant byte first.
 NOTE: We process both the First Operand and then also any Second Operand.
-------------------------------------------------------------------------------}
                while (FirstOperandMask[0] and $01) = $00  do
                begin
{-------------------------------------------------------------------------------
 First shift the FirstOperandMask.
-------------------------------------------------------------------------------}
                  for Lp := 0 to High(FirstOperandMask) do
                  begin
                    Carry := $00;
                    if Lp < High(FirstOperandMask) then
                      if (FirstOperandMask[Lp+1] and $01) = $01 then Carry := $80;
                    FirstOperandMask[Lp] := (FirstOperandMask[Lp] shr 1) or Carry;
                  end;

if (_LogLevel = LogDBG) then
  WriteLog('FirstOperandMask (Purged trailing zero bits):', FirstOperandMask);

{-------------------------------------------------------------------------------
 Then identically also shift the First Operand Bytes.
 Note, we know FirstOperandBytes is the same length as FirstOperandMask.
-------------------------------------------------------------------------------}
                  for Lp := 0 to High(FirstOperandBytes) do
                  begin
                    Carry := $00;
                    if Lp < High(FirstOperandBytes) then
                      if (FirstOperandBytes[Lp+1] and $01) = $01 then Carry := $80;
                    FirstOperandBytes[Lp] := (FirstOperandBytes[Lp] shr 1) or Carry;
                  end;

if (_LogLevel = LogDBG) then
  WriteLog('FirstOperandBytes (Purged trailing zero bits):', FirstOperandBytes);

                end;

{-------------------------------------------------------------------------------
 Now do the same for any existing Second Operand Bytes.
-------------------------------------------------------------------------------}
                while (Length(SecondOperandMask) > 0) and ((SecondOperandMask[0] and $01) = $00)  do
                begin
{-------------------------------------------------------------------------------
 First shift the SecondOperandMask.
-------------------------------------------------------------------------------}
                  for Lp := 0 to High(SecondOperandMask) do
                  begin
                    Carry := $00;
                    if Lp < High(SecondOperandMask) then
                      if (SecondOperandMask[Lp+1] and $01) = $01 then Carry := $80;
                    SecondOperandMask[Lp] := (SecondOperandMask[Lp] shr 1) or Carry;
                  end;

if (_LogLevel = LogDBG) then
  WriteLog('SecondOperandMask (Purged trailing zero bits):', SecondOperandMask);

{-------------------------------------------------------------------------------
 Then identically also shift the Second Operand Bytes.
 Note, we know SecondOperandBytes is the same length as SecondOperandMask.
-------------------------------------------------------------------------------}
                  for Lp := 0 to High(SecondOperandBytes) do
                  begin
                    Carry := $00;
                    if Lp < High(SecondOperandBytes) then
                      if (SecondOperandBytes[Lp+1] and $01) = $01 then Carry := $80;
                    SecondOperandBytes[Lp] := (SecondOperandBytes[Lp] shr 1) or Carry;
                  end;

if (_LogLevel = LogDBG) then
  WriteLog('SecondOperandBytes (Purged trailing zero bits):', SecondOperandBytes);

                end;

{-------------------------------------------------------------------------------
 Purge all leading (ie. most significant) zero bytes.
 Noting in Little Endian, leading (most significant) is the last byte.
-------------------------------------------------------------------------------}
                while (Length(FirstOperandMask) > 0) and (FirstOperandMask[High(FirstOperandMask)] = 0) do
                begin
                  Delete(FirstOperandMask,High(FirstOperandMask),1);
                  Delete(FirstOperandBytes,High(FirstOperandBytes),1);
                end;
                while (Length(SecondOperandMask) > 0) and (SecondOperandMask[High(SecondOperandMask)] = 0) do
                begin
                  Delete(SecondOperandMask,High(SecondOperandMask),1);
                  Delete(SecondOperandBytes,High(SecondOperandBytes),1);
                end;

if (_LogLevel = LogDBG) then
begin
  WriteLog('FirstOperandBytes (Purged leading zero bytes):', FirstOperandBytes);
  WriteLog('SecondOperandBytes (Purged leading zero bytes):', SecondOperandBytes);
end;

{-------------------------------------------------------------------------------
 Capture the byte normalised actual byte lengths of the Operands, to allow us
 to later represent the Operand value as it's correct length Hex string.
-------------------------------------------------------------------------------}
                FirstOperandLength := Length(FirstOperandBytes);
                SecondOperandLength := Length(SecondOperandBytes);

{-------------------------------------------------------------------------------
 Now is a good time to actually apply the Operand Masks to the OperandBytes, to
 extract the Operands themselves (now know to be right aligned and condensed to
 include only the significant bytes that contain the Operands).
 Note that at this point we know the FirstOperand consists of at least 1 byte!
 (otherwise it would have been trapped after the post trailing zero purge)
 We are unsure about SecondOperand length, however the standard High() function
 returns -1 for a zero length array (so the For loop won't execute if empty).
-------------------------------------------------------------------------------}
                for Lp := 0 to High(FirstOperandMask) do
                  FirstOperandBytes[Lp] := FirstOperandBytes[Lp] and FirstOperandMask[Lp];

                for Lp := 0 to High(SecondOperandMask) do
                  SecondOperandBytes[Lp] := SecondOperandBytes[Lp] and SecondOperandMask[Lp];

if (_LogLevel = LogDBG) then
begin
  WriteLog('FirstOperand (extracted from OperandBytes):', FirstOperandBytes);
  WriteLog('SecondOperand (extracted from OperandBytes):', SecondOperandBytes);
end;

{-------------------------------------------------------------------------------
 Now we determine if any required left bit padding (most significant bits),
 to normalise as a 8, 16, 32, or 64 bit value, should be 0 or 1 bit values.
 Specifically, if the Operand value is to be treated as Unsigned, then the bit
 padding will always by 0 (so we default is MSB Set to False).
 However, if the Operand is to be treated as a Signed value, then we need to
 sign extend the most significant Operand bit.
 NOTE: We process both the First Operand and then also any Second Operand.
-------------------------------------------------------------------------------}
                isFirstOperandMsbSet := False;
                if _OpcodeDefinitions[ByteIndex].FirstOperandSignedUnsigned = OperandSigned then
                begin
{-------------------------------------------------------------------------------
 Identify single bit mask for the most significant mask 1 bit.
 This is needed for a signed FirstOperand to allow for final sign extend.
 At his point we know the most significant mask bit is in the leading byte,
 so we only need a resulting single byte bit mask for this purpose.
 Noting, Little Endian leading (most significant) is the last byte.
-------------------------------------------------------------------------------}
                  MsbMask := $80;
                  TempBytes := Copy(FirstOperandMask);
                  while TempBytes[High(TempBytes)] and $80 = $00  do
                  begin
                    TempBytes[High(TempBytes)] := TempBytes[High(TempBytes)] shl 1;
                    MsbMask := MsbMask shr 1;
                  end;
{-------------------------------------------------------------------------------
 Now if the Signed most significant bit was set, we update isFirstOperandMsbSet,
 and update the FirstOperand with '1' sign-extend bits.
-------------------------------------------------------------------------------}
                  if (FirstOperandBytes[High(FirstOperandBytes)] and MsbMask) <> 0 then
                  begin
                    isFirstOperandMsbSet := True;
                    case MsbMask of
                      $01: FirstOperandBytes[High(FirstOperandBytes)] := FirstOperandBytes[High(FirstOperandBytes)] or $FE;
                      $02: FirstOperandBytes[High(FirstOperandBytes)] := FirstOperandBytes[High(FirstOperandBytes)] or $FC;
                      $04: FirstOperandBytes[High(FirstOperandBytes)] := FirstOperandBytes[High(FirstOperandBytes)] or $F8;
                      $08: FirstOperandBytes[High(FirstOperandBytes)] := FirstOperandBytes[High(FirstOperandBytes)] or $F0;
                      $10: FirstOperandBytes[High(FirstOperandBytes)] := FirstOperandBytes[High(FirstOperandBytes)] or $E0;
                      $20: FirstOperandBytes[High(FirstOperandBytes)] := FirstOperandBytes[High(FirstOperandBytes)] or $C0;
                      $40: FirstOperandBytes[High(FirstOperandBytes)] := FirstOperandBytes[High(FirstOperandBytes)] or $80;
                    end;

                  end;
                end;

{-------------------------------------------------------------------------------
 Now do the same for any existing Second Operand Bytes.
-------------------------------------------------------------------------------}
                isSecondOperandMsbSet := False;
                if _OpcodeDefinitions[ByteIndex].SecondOperandSignedUnsigned = OperandSigned then
                begin
{-------------------------------------------------------------------------------
 Identify single bit mask for the most significant mask 1 bit.
 This is needed for a signed SecondOperand to allow for final sign extend.
 At his point we know the most significant mask bit is in the leading byte,
 so we only need a resulting single byte bit mask for this purpose.
 Noting, Little Endian leading (most significant) is the last byte.
-------------------------------------------------------------------------------}
                  MsbMask := $80;
                  TempBytes := Copy(SecondOperandMask);
                  while TempBytes[High(TempBytes)] and $80 = $00  do
                  begin
                    TempBytes[High(TempBytes)] := TempBytes[High(TempBytes)] shl 1;
                    MsbMask := MsbMask shr 1;
                  end;
{-------------------------------------------------------------------------------
 Now if the Signed most significant bit was set, we update isSecondOperandMsbSet
 and update the SecondOperand with '1' sign-extend bits.
-------------------------------------------------------------------------------}
                  if (SecondOperandBytes[High(SecondOperandBytes)] and MsbMask) <> 0 then
                  begin
                    isSecondOperandMsbSet := True;
                    case MsbMask of
                      $01: SecondOperandBytes[High(SecondOperandBytes)] := SecondOperandBytes[High(SecondOperandBytes)] or $FE;
                      $02: SecondOperandBytes[High(SecondOperandBytes)] := SecondOperandBytes[High(SecondOperandBytes)] or $FC;
                      $04: SecondOperandBytes[High(SecondOperandBytes)] := SecondOperandBytes[High(SecondOperandBytes)] or $F8;
                      $08: SecondOperandBytes[High(SecondOperandBytes)] := SecondOperandBytes[High(SecondOperandBytes)] or $F0;
                      $10: SecondOperandBytes[High(SecondOperandBytes)] := SecondOperandBytes[High(SecondOperandBytes)] or $E0;
                      $20: SecondOperandBytes[High(SecondOperandBytes)] := SecondOperandBytes[High(SecondOperandBytes)] or $C0;
                      $40: SecondOperandBytes[High(SecondOperandBytes)] := SecondOperandBytes[High(SecondOperandBytes)] or $80;
                    end;

                  end;
                end;

{-------------------------------------------------------------------------------
 Now, based on is Operand MSB Set we pad out the Operand to 1,2,4 or 8 bytes.
 ie. An 8, 16, 32, or 64 bit value.
 isFirstOperandMsbSet now determines if we need to pad with 1's ($FF) or 0's ($00).
 Noting in Little Endian, the leading (most significant) is the last byte.
-------------------------------------------------------------------------------}
                if isFirstOperandMsbSet
                  then while Length(FirstOperandBytes) in [0,3,5..7] do Insert($FF,FirstOperandBytes,Length(FirstOperandBytes))
                  else while Length(FirstOperandBytes) in [0,3,5..7] do Insert($00,FirstOperandBytes,Length(FirstOperandBytes));
                if isSecondOperandMsbSet
                  then while Length(SecondOperandBytes) in [0,3,5..7] do Insert($FF,SecondOperandBytes,Length(SecondOperandBytes))
                  else while Length(SecondOperandBytes) in [0,3,5..7] do Insert($00,SecondOperandBytes,Length(SecondOperandBytes));

(*
{-------------------------------------------------------------------------------
 Now, based on is Operand MSB Set, we pad out the Operand to 8 bytes (64 bit).
 is OperandMsbSet now determines if we need to pad with 1's ($FF) or 0's ($00).
 Noting in Little Endian, the leading (most significant) is the last byte.
 *******************************************************************************
 NOTE: Refer Note in GetOperandStr(). Below is version of above, where the
 passed prmOperandBytes is normalised to a consistently 64 bit value.
 *******************************************************************************
-------------------------------------------------------------------------------}
                if isFirstOperandMsbSet
                  then while Length(FirstOperandBytes) < 8 do Insert($FF,FirstOperandBytes,Length(FirstOperandBytes))
                  else while Length(FirstOperandBytes) < 8 do Insert($00,FirstOperandBytes,Length(FirstOperandBytes));
                if isSecondOperandMsbSet
                  then while Length(SecondOperandBytes) < 8 do Insert($FF,SecondOperandBytes,Length(SecondOperandBytes))
                  else while Length(SecondOperandBytes) < 8 do Insert($00,SecondOperandBytes,Length(SecondOperandBytes));
*)

{-------------------------------------------------------------------------------
 We can finally now convert the Operand values to their string representations,
 for rendering.  This is performed via GetOperandStr();
-------------------------------------------------------------------------------}
                FirstOperandStr := GetOperandStr(_OpcodeDefinitions[ByteIndex].FirstOperandHexDec, _OpcodeDefinitions[ByteIndex].FirstOperandSignedUnsigned, FirstOperandLength, FirstOperandBytes);
                SecondOperandStr := GetOperandStr(_OpcodeDefinitions[ByteIndex].SecondOperandHexDec, _OpcodeDefinitions[ByteIndex].SecondOperandSignedUnsigned, SecondOperandLength, SecondOperandBytes);

(*
                if (_OpcodeDefinitions[ByteIndex].FirstOperandHexDec = OperandHex) then
                begin
{-------------------------------------------------------------------------------
 The following commented-out code was originally used when we simply rendered
 the raw Hex values, irrespective of them being Signed or Unsigned.
 The original assumption was that the viewer would understand that a relative
 reference (for example) of $FF, would equate to -1 (two's complement).
 This was based on my own personal history of manually counting back branch
 relative offsets in hand assembled machine code. ie. FF.. FE.. FD.. etc.
 However Maël pointed out that -ve representation was also appropriate for Hex.
//                  ReverseByteOrder(FirstOperandBytes);
//                  SetLength(FirstOperandStr, Length(FirstOperandBytes) * 2);
//                  BinToHex(FirstOperandBytes,PWideChar(FirstOperandStr),Length(FirstOperandBytes));
//                  FirstOperandStr := '$'+FirstOperandStr;
-------------------------------------------------------------------------------}
                  if (_OpcodeDefinitions[ByteIndex].FirstOperandSignedUnsigned = OperandSigned) then
                  begin
                    case Length(FirstOperandBytes) of
                      1: if (PInt8(@FirstOperandBytes[0])^ < 0) then FirstOperandStr := '-$' + IntToHex(-PInt8(@FirstOperandBytes[0])^,2)
                                                            else FirstOperandStr := '$' + IntToHex(PInt8(@FirstOperandBytes[0])^);
                      2: if (PInt16(@FirstOperandBytes[0])^ < 0) then FirstOperandStr := '-$' + IntToHex(-PInt16(@FirstOperandBytes[0])^,4)
                                                             else FirstOperandStr := '$' + IntToHex(PInt16(@FirstOperandBytes[0])^);
                      4: if (PInt32(@FirstOperandBytes[0])^ < 0) then FirstOperandStr := '-$' + IntToHex(-Pint32(@FirstOperandBytes[0])^,8)
                                                             else FirstOperandStr := '$' + IntToHex(Pint32(@FirstOperandBytes[0])^);
                      8: if (PInt64(@FirstOperandBytes[0])^ < 0) then FirstOperandStr := '-$' + IntToHex(-Pint64(@FirstOperandBytes[0])^,16)
                                                             else FirstOperandStr := '$' + IntToHex(Pint64(@FirstOperandBytes[0])^);
                    end;
                  end
                  else
                  begin
                    case Length(FirstOperandBytes) of
                      1: FirstOperandStr := '$' + IntToHex(PUInt8(@FirstOperandBytes[0])^);
                      2: FirstOperandStr := '$' + IntToHex(PUInt16(@FirstOperandBytes[0])^);
                      4: FirstOperandStr := '$' + IntToHex(PUint32(@FirstOperandBytes[0])^);
                      8: FirstOperandStr := '$' + IntToHex(PUint64(@FirstOperandBytes[0])^);
                    end;
                  end;
                end
                else
                begin
{-------------------------------------------------------------------------------
 Otherwise, for Dec format we need to convert, based on the FirstOperand being
 either a Signed or Unsigned value.
-------------------------------------------------------------------------------}
                  if _OpcodeDefinitions[ByteIndex].FirstOperandSignedUnsigned = OperandSigned then
                  begin
                    case Length(FirstOperandBytes) of
                      1: FirstOperandStr := IntToStr(PInt8(@FirstOperandBytes[0])^);
                      2: FirstOperandStr := IntToStr(PInt16(@FirstOperandBytes[0])^);
                      4: FirstOperandStr := IntToStr(Pint32(@FirstOperandBytes[0])^);
                      8: FirstOperandStr := IntToStr(Pint64(@FirstOperandBytes[0])^);
                    end;
                  end
                  else
                  begin
                    case Length(FirstOperandBytes) of
                      1: FirstOperandStr := UIntToStr(PUInt8(@FirstOperandBytes[0])^);
                      2: FirstOperandStr := UIntToStr(PUInt16(@FirstOperandBytes[0])^);
                      4: FirstOperandStr := UIntToStr(PUint32(@FirstOperandBytes[0])^);
                      8: FirstOperandStr := UIntToStr(PUint64(@FirstOperandBytes[0])^);
                    end;
                  end;
                end;
*)


{-------------------------------------------------------------------------------
 The Final step is to just replace any output AssemblyString FirstOperand and
 SecondOperand wildcards with the final First & Second Operand Strings. Yay!
-------------------------------------------------------------------------------}
                AssemblyString := StringReplace(AssemblyString,FirstOperandWildcard,FirstOperandStr,[rfReplaceAll]);
                AssemblyString := StringReplace(AssemblyString,SecondOperandWildcard,SecondOperandStr,[rfReplaceAll]);

              end;
            end;
          end;
        end;
      end;
      if (not MatchFound) then inc(ByteIndex);
    end;  // while
  end;
  if MatchFound then
  begin
   Result:=True
  end
  else
  begin
    AssemblyString := '';
    DisassembledByteCount := 0;
    Result:=False;
  end;
end;

end.

