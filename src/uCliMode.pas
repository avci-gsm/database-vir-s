unit uCliMode;

interface

type
  CliMode = class
    class function ShouldRunCli: Boolean; static;
    class function RunCli: Integer; static;
  end;

implementation

uses
  SysUtils, Classes, Generics.Collections, uStatus, uFlash, uGroupFlasher,
  uPit, uSysfsUSB, uWinUSBDevice, uWinUSBConn, uTcpTransport, uByteTransport;

type
  TCliArgs = record
    Help: Boolean;
    ListDevices: Boolean;
    Wireless: Boolean;
    NoReboot: Boolean;
    Target: string;
    PitPath: string;
    BL: string;
    AP: string;
    CP: string;
    CSC: string;
    UserData: string;
  end;

function IsCliTrigger(const Arg: string): Boolean;
const
  Triggers: array[0..10] of string = (
    '-h', '--help', '--list', '--wireless', '--no-reboot',
    '--use-pit', '--target', '-b', '-a', '-c', '-s'
  );
var
  I: Integer;
begin
  for I := Low(Triggers) to High(Triggers) do
    if SameText(Arg, Triggers[I]) then
      Exit(True);
  Result := False;
end;

function ParseArgs: TCliArgs;
var
  I: Integer;
  Arg: string;
begin
  FillChar(Result, SizeOf(Result), 0);
  I := 1;
  while I <= ParamCount do
  begin
    Arg := ParamStr(I);
    if (Arg = '-h') or (Arg = '--help') then
      Result.Help := True
    else if Arg = '--list' then
      Result.ListDevices := True
    else if Arg = '--wireless' then
      Result.Wireless := True
    else if Arg = '--no-reboot' then
      Result.NoReboot := True
    else if Arg = '--target' then
    begin
      Inc(I);
      if I <= ParamCount then Result.Target := ParamStr(I);
    end
    else if Arg = '--use-pit' then
    begin
      Inc(I);
      if I <= ParamCount then Result.PitPath := ParamStr(I);
    end
    else if Arg = '-b' then
    begin
      Inc(I);
      if I <= ParamCount then Result.BL := ParamStr(I);
    end
    else if Arg = '-a' then
    begin
      Inc(I);
      if I <= ParamCount then Result.AP := ParamStr(I);
    end
    else if Arg = '-c' then
    begin
      Inc(I);
      if I <= ParamCount then Result.CP := ParamStr(I);
    end
    else if Arg = '-s' then
    begin
      Inc(I);
      if I <= ParamCount then Result.CSC := ParamStr(I);
    end
    else if Arg = '-u' then
    begin
      Inc(I);
      if I <= ParamCount then Result.UserData := ParamStr(I);
    end;
    Inc(I);
  end;
end;

procedure PrintUsage;
begin
  WriteLn('Usage:');
  WriteLn('  BrokkrFlash [CLI options]');
  WriteLn;
  WriteLn('CLI options:');
  WriteLn('  -h, --help                 Show this help');
  WriteLn('  --list                     List Samsung devices');
  WriteLn('  -b <path.tar[.md5]>        BL file');
  WriteLn('  -a <path.tar[.md5]>        AP file');
  WriteLn('  -c <path.tar[.md5]>        CP file');
  WriteLn('  -s <path.tar[.md5]>        CSC file');
  WriteLn('  -u <path.tar[.md5]>        USERDATA file');
  WriteLn('  --use-pit <path.pit>       Optional PIT file');
  WriteLn('  --no-reboot                Do not reboot at end');
  WriteLn('  --wireless                 Flash via wireless');
  WriteLn('  --target <sysname>         Target device');
end;

{ CliMode }

class function CliMode.ShouldRunCli: Boolean;
var
  I: Integer;
begin
  for I := 1 to ParamCount do
    if IsCliTrigger(ParamStr(I)) then
      Exit(True);
  Result := False;
end;

class function CliMode.RunCli: Integer;
var
  Args: TCliArgs;
  Inputs: TStringList;
  Sources: TList<TImageSpec>;
  ExpandResult: TBrokkrResult<TList<TImageSpec>>;
  Cfg: TFlashCfg;
  UI: TFlashUI;
  Devices: TList<TTarget>;
  Dev: TTarget;
  Conn: TWinUSBConnection;
  USBDev: TWinUSBDevice;
  TcpConn: TTcpConnection;
  DevList: TList<TUsbDeviceSysfsInfo>;
  Filter: TEnumerateFilter;
  DevInfo: TUsbDeviceSysfsInfo;
  PitData: TBytes;
  FS: TFileStream;
  St: TBrokkrStatus;
  I: Integer;
begin
  Result := 0;
  Args := ParseArgs;

  if Args.Help then
  begin
    PrintUsage;
    Exit(0);
  end;

  if Args.ListDevices then
  begin
    Filter.Vendor := SAMSUNG_VID;
    Filter.Products := TArray<Word>.Create($6601, $685D, $68C3);
    DevList := EnumerateUSBDevices(Filter);
    try
      if DevList.Count = 0 then
        WriteLn('No Samsung download-mode devices found.')
      else
      begin
        WriteLn(Format('Found %d device(s):', [DevList.Count]));
        for I := 0 to DevList.Count - 1 do
          WriteLn('  ', DevList[I].Describe);
      end;
    finally
      DevList.Free;
    end;
    Exit(0);
  end;

  Inputs := TStringList.Create;
  try
    if Args.BL <> '' then Inputs.Add(Args.BL);
    if Args.AP <> '' then Inputs.Add(Args.AP);
    if Args.CP <> '' then Inputs.Add(Args.CP);
    if Args.CSC <> '' then Inputs.Add(Args.CSC);
    if Args.UserData <> '' then Inputs.Add(Args.UserData);

    if (Inputs.Count = 0) and (Args.PitPath = '') then
    begin
      WriteLn('Error: At least one file is required (-b -a -c -s -u or --use-pit)');
      PrintUsage;
      Exit(1);
    end;

    ExpandResult := ExpandInputsTarOrRaw(Inputs);
    if not ExpandResult.IsOK then
    begin
      WriteLn('Error: ', ExpandResult.Error);
      Exit(1);
    end;
    Sources := ExpandResult.Value;
  finally
    Inputs.Free;
  end;

  SetLength(PitData, 0);
  if Args.PitPath <> '' then
  begin
    try
      FS := TFileStream.Create(Args.PitPath, fmOpenRead);
      try
        SetLength(PitData, FS.Size);
        FS.ReadBuffer(PitData[0], FS.Size);
      finally
        FS.Free;
      end;
    except
      on E: Exception do
      begin
        WriteLn('Error reading PIT: ', E.Message);
        Exit(1);
      end;
    end;
  end;

  Devices := TList<TTarget>.Create;
  try
    if Args.Wireless then
    begin
      WriteLn('Waiting for wireless connection on port ', WIRELESS_PORT, '...');
      TcpConn := TTcpConnection.Create;
      St := TcpConn.Accept;
      if not St.IsOK then
      begin
        WriteLn('Error: ', St.Error);
        Exit(1);
      end;

      Dev := TTarget.Create;
      Dev.ID := 'wireless';
      Dev.Link := TcpConn;
      Devices.Add(Dev);
    end
    else
    begin
      Filter.Vendor := SAMSUNG_VID;
      Filter.Products := TArray<Word>.Create($6601, $685D, $68C3);
      DevList := EnumerateUSBDevices(Filter);
      try
        if DevList.Count = 0 then
        begin
          WriteLn('No Samsung download-mode devices found.');
          Exit(1);
        end;

        if Args.Target <> '' then
        begin
          DevInfo := FindBySysName(Args.Target);
          if DevInfo.SysName = '' then
          begin
            WriteLn('Target not found: ', Args.Target);
            Exit(1);
          end;
        end
        else
          DevInfo := DevList[0];

        WriteLn('Using device: ', DevInfo.Describe);
        USBDev := TWinUSBDevice.Create(DevInfo.DevNodePath);
        Conn := TWinUSBConnection.Create(USBDev);
        St := Conn.Open;
        if not St.IsOK then
        begin
          WriteLn('Error: ', St.Error);
          Exit(1);
        end;

        Dev := TTarget.Create;
        Dev.ID := DevInfo.SysName;
        Dev.Link := Conn;
        Devices.Add(Dev);
      finally
        DevList.Free;
      end;
    end;

    Cfg := TFlashCfg.Default;
    Cfg.RebootAfter := not Args.NoReboot;

    UI.OnStage := procedure(const Stage: string)
    begin
      WriteLn('[STAGE] ', Stage);
    end;

    UI.OnProgress := procedure(Done, Total, ItemDone, ItemTotal: UInt64)
    begin
      if Total > 0 then
        Write(Format(#13'  Progress: %d / %d MB (%d%%)',
          [Done div (1024*1024), Total div (1024*1024), (Done * 100) div Total]));
    end;

    UI.OnError := procedure(const Msg: string)
    begin
      WriteLn('[ERROR] ', Msg);
    end;

    UI.OnDone := procedure
    begin
      WriteLn;
      WriteLn('[DONE] Flash completed successfully!');
    end;

    UI.OnItemActive := procedure(Idx: Integer)
    begin
      WriteLn(Format('[ITEM %d] Flashing...', [Idx]));
    end;

    UI.OnItemDone := procedure(Idx: Integer)
    begin
      WriteLn(Format('[ITEM %d] Done', [Idx]));
    end;

    St := FlashDevices(Devices, Sources, PitData, Cfg, UI);
    if not St.IsOK then
    begin
      WriteLn('[FAILED] ', St.Error);
      Exit(1);
    end;
  finally
    for I := 0 to Devices.Count - 1 do
      Devices[I].Free;
    Devices.Free;
    Sources.Free;
  end;
end;

end.
