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

unit DasmConverter;

interface

uses
  Classes, SysUtils, StrUtils, IniFiles,
  DataInspectorShared, DataInspectorPluginServer,
  CpuDefinition;

const
{-------------------------------------------------------------------------------
 The maximum number of disassembly types permitted.
 This needs to align with the total number of TDasmConverter class declarations
 (see duplicate class comment below).
 A restriction on the number of supported Disassembly types is acceptable,
 given each type adds extra HxD startup overhead with defintion file loading.
-------------------------------------------------------------------------------}
  MaxDasmTypesCount = 8;

type
  TDasmConverter = class(TExternalDataTypeConverter)
    private
      CpuDefinition: TCpuDefinition;

    public
      constructor Create; override;

      procedure ChangeByteOrder(Bytes: PByte; ByteCount: Integer;
        TargetByteOrder: TByteOrder); override;
      function BytesToStr(Bytes: PByte; ByteCount: Integer;
        IntegerDisplayOption: TIntegerDisplayOption;
        out ConvertedByteCount: Integer;
        var ConvertedStr: string): TBytesToStrError; override;
      function StrToBytes(const Str: string;
        IntegerDisplayOption: TIntegerDisplayOption;
        var ConvertedBytes: TBytes): TStrToBytesError; override;
  end;

{-------------------------------------------------------------------------------
 The following duplicate class declarations are a workaround, to allow multiple
 class references to be registered with HxD.
 eg. For MaxDasmTypesCount = 8, we need 1..7 duplicate classes.
 Perhaps there is a better way to do this, but this is acceptable given that
 a restriction on the number of supported Disassembly types is acceptable.
 (Each type adds more HxD startup overhead with defintion file loading).
 See also CurrentDasmType (.Create and Initialisation code) for usage.
-------------------------------------------------------------------------------}
  TDasmConverter1 = class(TDasmConverter);
  TDasmConverter2 = class(TDasmConverter);
  TDasmConverter3 = class(TDasmConverter);
  TDasmConverter4 = class(TDasmConverter);
  TDasmConverter5 = class(TDasmConverter);
  TDasmConverter6 = class(TDasmConverter);
  TDasmConverter7 = class(TDasmConverter);


implementation

type
  TIniSettings = record
    Name: string;
    MaxInstructionByteCount: Int16;
    OperandEndianness: string;
    FirstOperandWildcard: string;
    SecondOperandWildcard: string;
    DefinitionFilePath: string;
    DefinitionFileName: string;
    DefinitionLogEnable: string;
    DefinitionLogPath: string;
  end;

var
  DasmTypesList: TStringList;
  DasmTypesCount: Int16;
  CurrentDasmType: Int16;
  IniSettings: Array[0..MaxDasmTypesCount-1] of TIniSettings;

{ TDasmConverter }

constructor TDasmConverter.Create;
begin
  inherited;
  CurrentDasmType := 0;
  if self.ClassName = 'TDasmConverter1' then CurrentDasmType := 1
  else if self.ClassName = 'TDasmConverter2' then CurrentDasmType := 2
  else if self.ClassName = 'TDasmConverter3' then CurrentDasmType := 3
  else if self.ClassName = 'TDasmConverter4' then CurrentDasmType := 4
  else if self.ClassName = 'TDasmConverter5' then CurrentDasmType := 5
  else if self.ClassName = 'TDasmConverter6' then CurrentDasmType := 6
  else if self.ClassName = 'TDasmConverter7' then CurrentDasmType := 7;

  CpuDefinition:= TCpuDefinition.Create(
                  IncludeTrailingPathDelimiter(IniSettings[CurrentDasmType].DefinitionFilePath)+IniSettings[CurrentDasmType].DefinitionFileName,
                  IniSettings[CurrentDasmType].OperandEndianness,
                  IniSettings[CurrentDasmType].FirstOperandWildcard,
                  IniSettings[CurrentDasmType].SecondOperandWildcard,
                  IniSettings[CurrentDasmType].DefinitionLogEnable,
                  IniSettings[CurrentDasmType].DefinitionLogPath);

  FMaxTypeSize := IniSettings[CurrentDasmType].MaxInstructionByteCount;

  if (AnsiLowerCase(IniSettings[CurrentDasmType].DefinitionLogEnable) = 'dbg')
     or (AnsiLowerCase(IniSettings[CurrentDasmType].DefinitionLogEnable) = 'debug')
    then FTypeName := IniSettings[CurrentDasmType].Name+' ['+IntToStr(CpuDefinition.OpcodeCount)+']'
    else FTypeName := IniSettings[CurrentDasmType].Name;

  FFriendlyTypeName := FTypeName;

  FWidth := dtwVariable;
  FSupportedByteOrders := [];
{-------------------------------------------------------------------------------
 FSupportsStrToBytes added in HxD 2.5.0.0 release, to provide support for
 a dialog to notify that the plugin does not support Data inspector editing.
 ie. Comment out the below line for HxD 2.4.0.0 plug-in.
     Uncomment below line for HxD 2.5.0.0 release.
-------------------------------------------------------------------------------}
  FSupportsStrToBytes := False;
end;

(*
procedure ReverseByteOrder(var Values: TBytes);
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
*)

procedure TDasmConverter.ChangeByteOrder(Bytes: PByte; ByteCount: Integer;
  TargetByteOrder: TByteOrder);
begin
end;

function TDasmConverter.BytesToStr(Bytes: PByte; ByteCount: Integer;
  IntegerDisplayOption: TIntegerDisplayOption; out ConvertedByteCount: Integer;
  var ConvertedStr: string): TBytesToStrError;
var ByteArray: TBytes;
  Lp: Integer;
begin
{-------------------------------------------------------------------------------
 Make sure we have actually been given some bytes to convert to a string!
 ------------------------------------------------------------------------------}
  if (ByteCount > 0) then
  begin
{-------------------------------------------------------------------------------
 Capture the passed Bytes sequence into a local TBytes Array.
-------------------------------------------------------------------------------}
    SetLength(ByteArray, ByteCount);
    for Lp := 0 to ByteCount - 1 do
    Begin
     ByteArray[Lp] := (Bytes + Lp)^;
    End;
{-------------------------------------------------------------------------------
 See if we can Disassemble the Byte sequence into an Assembly instruction.
-------------------------------------------------------------------------------}
    if CpuDefinition.DisassembleInstruction(ByteArray, ConvertedStr, ConvertedByteCount)
      then Result := btseNone
      else Result := btseInvalidBytes;

  end
  else Result := btseBytesTooShort;
end;

function TDasmConverter.StrToBytes(const Str: string;
  IntegerDisplayOption: TIntegerDisplayOption;
  var ConvertedBytes: TBytes): TStrToBytesError;
begin
  Result := stbeNone;
end;

procedure ImportIniSettings;
const cr = #13;
var
  RegINI:TINIFile;
  INIFileName: string;
  IniSection: string;
  DasmTypes: string;
  Lp: Int16;
begin
  INIFileName:=ChangeFileExt(SysUtils.GetModuleName(HInstance), '.ini');
  if FileExists(INIFileName) then
  begin
    RegINI:=TINIFile.Create(INIFileName);
    try
      try
{-------------------------------------------------------------------------------
 Purge all spaces etc. from the INI supplied DasmTypes comma separated list.
-------------------------------------------------------------------------------}
        DasmTypes:=Trim(StringReplace(RegINI.ReadString('General', 'DasmTypes', ''),' ','',[rfReplaceAll,rfIgnoreCase]));
        if (DasmTypes <> '') then
        begin
{-------------------------------------------------------------------------------
 Convert the comma seperated DasmTypes string value to a stringlist.
-------------------------------------------------------------------------------}
          DasmTypes:=StringReplace(DasmTypes,',',cr,[rfReplaceAll,rfIgnoreCase]);
          DasmTypesList.Text:=DasmTypes;
          DasmTypesCount := DasmTypesList.Count;
          if (DasmTypesCount > MaxDasmTypesCount) then DasmTypesCount := MaxDasmTypesCount;

          for Lp := 0 to DasmTypesCount - 1 do
          begin
            IniSection:=DasmTypesList[Lp];
            with IniSettings[Lp] do
            begin
{-------------------------------------------------------------------------------
 For each DasmType we set the Name of the Disassembly type by utilising the
 DataInspectorPlugin string variable facility for automatic localizing of the
 "Disassembly" name, as it appears in the HxD DataInspector grid.
 The resulting Name will therefore be in the form "Disassembly (xxx)", where
 xxx is the .ini specified DasmType (IniSection name).
 Note that any embedded double quotes in the provided DasmType are escaped,
 (as required by the string cariable facility).
 ------------------------------------------------------------------------------}
              Name:='{s:Disassembly("'+StringReplace(IniSection,'"','""',[rfReplaceAll])+'")}';

{-------------------------------------------------------------------------------
 Now we load the IniSection options specified for this DasmType
 ------------------------------------------------------------------------------}
              MaxInstructionByteCount:=RegINI.ReadInteger(IniSection, 'MaxInstructionByteCount', 1);

              OperandEndianness:=Trim(RegINI.ReadString(IniSection, 'OperandEndianness', 'Little'));
              FirstOperandWildcard:=Trim(RegINI.ReadString(IniSection, 'FirstOperandWildcard', '?'));
              SecondOperandWildcard:=Trim(RegINI.ReadString(IniSection, 'SecondOperandWildcard', '^'));

              DefinitionFilePath:=Trim(RegINI.ReadString(IniSection, 'DefinitionFilePath', ''));
              DefinitionFileName:=Trim(RegINI.ReadString(IniSection, 'DefinitionFileName', ''));

{-------------------------------------------------------------------------------
 DefinitionLogEnable was changed from boolean to string type, to allow for an
 undocumented value of 'DBG' (or debug), for additional debug logging.
 Debug simply adds logging of CpuDefinition.DisassembleInstruction processing.
-------------------------------------------------------------------------------}
//              DefinitionLogEnable:=RegINI.ReadBool(IniSection, 'DefinitionLogEnable', False);
              DefinitionLogEnable:=AnsiUpperCase(Trim(RegINI.ReadString(IniSection, 'DefinitionLogEnable', '')));
              DefinitionLogPath:=Trim(RegINI.ReadString(IniSection, 'DefinitionLogPath', ''));

            end;

          end;
        end;
      except
      end;
    finally
      RegINI.Destroy;
    end;
  end; //if FileExists
end;

initialization
  DasmTypesCount := 0;
  DasmTypesList:=TStringList.Create;
  try
    try
      ImportIniSettings;

      for CurrentDasmType := 0 to DasmTypesCount - 1 do
      begin
        case CurrentDasmType of
          0: RegisterDataTypeConverter(TDasmConverter);
          1: RegisterDataTypeConverter(TDasmConverter1);
          2: RegisterDataTypeConverter(TDasmConverter2);
          3: RegisterDataTypeConverter(TDasmConverter3);
          4: RegisterDataTypeConverter(TDasmConverter4);
          5: RegisterDataTypeConverter(TDasmConverter5);
          6: RegisterDataTypeConverter(TDasmConverter6);
          7: RegisterDataTypeConverter(TDasmConverter7);
        end;
      end;
    except
    end;
  finally
    DasmTypesList.Free;
  end;
end.

