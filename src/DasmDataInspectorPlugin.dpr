library DasmDataInspectorPlugin;

uses
  DataInspectorShared in 'DataInspectorShared.pas',
  DataInspectorPluginServer in 'DataInspectorPluginServer.pas',
  DasmConverter in 'DasmConverter.pas',
  CpuDefinition in 'CpuDefinition.pas';

{$R *.res}

exports
  GetDataTypeConverterClassIDs,

  CreateConverter,
  DestroyConverter,
  AssignConverter,
  ChangeByteOrder,
  BytesToStr,
  StrToBytes;

begin
end.

