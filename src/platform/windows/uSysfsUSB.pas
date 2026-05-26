unit uSysfsUSB;

interface

uses
  SysUtils, Classes, Windows, Generics.Collections;

type
  TUsbDeviceSysfsInfo = record
    SysName: string;
    Vendor: Word;
    Product: Word;
    DevNodePath: string;
    function Describe: string;
  end;

  TEnumerateFilter = record
    Vendor: Word;
    Products: TArray<Word>;
  end;

function EnumerateUSBDevices(const Filter: TEnumerateFilter): TList<TUsbDeviceSysfsInfo>;
function FindBySysName(const SysName: string): TUsbDeviceSysfsInfo;
function IsOdinProduct(PID: Word): Boolean;

implementation

uses
  Registry;

const
  SAMSUNG_VID = $04E8;
  ODIN_PIDS: array[0..2] of Word = ($6601, $685D, $68C3);

  GUID_DEVINTERFACE_USB_DEVICE: TGUID = '{A5DCBF10-6530-11D2-901F-00C04FB951ED}';

function IsOdinProduct(PID: Word): Boolean;
var
  I: Integer;
begin
  for I := Low(ODIN_PIDS) to High(ODIN_PIDS) do
    if ODIN_PIDS[I] = PID then
      Exit(True);
  Result := False;
end;

function TUsbDeviceSysfsInfo.Describe: string;
begin
  Result := Format('%s (VID=%04X PID=%04X)', [SysName, Vendor, Product]);
end;

function EnumerateUSBDevices(const Filter: TEnumerateFilter): TList<TUsbDeviceSysfsInfo>;
var
  Reg: TRegistry;
  Names: TStringList;
  I, J: Integer;
  Path, VIDStr, PIDStr: string;
  VID, PID: Word;
  Info: TUsbDeviceSysfsInfo;
  Matched: Boolean;
begin
  Result := TList<TUsbDeviceSysfsInfo>.Create;

  Reg := TRegistry.Create(KEY_READ);
  Names := TStringList.Create;
  try
    Reg.RootKey := HKEY_LOCAL_MACHINE;
    if not Reg.OpenKeyReadOnly('SYSTEM\CurrentControlSet\Enum\USB') then
      Exit;

    Reg.GetKeyNames(Names);
    for I := 0 to Names.Count - 1 do
    begin
      Path := Names[I];
      // Parse VID_xxxx&PID_xxxx
      VIDStr := '';
      PIDStr := '';

      J := Pos('VID_', UpperCase(Path));
      if J > 0 then
        VIDStr := Copy(Path, J + 4, 4);

      J := Pos('PID_', UpperCase(Path));
      if J > 0 then
        PIDStr := Copy(Path, J + 4, 4);

      if (VIDStr = '') or (PIDStr = '') then
        Continue;

      VID := Word(StrToIntDef('$' + VIDStr, 0));
      PID := Word(StrToIntDef('$' + PIDStr, 0));

      if (Filter.Vendor <> 0) and (VID <> Filter.Vendor) then
        Continue;

      if Length(Filter.Products) > 0 then
      begin
        Matched := False;
        for J := Low(Filter.Products) to High(Filter.Products) do
          if Filter.Products[J] = PID then
          begin
            Matched := True;
            Break;
          end;
        if not Matched then
          Continue;
      end;

      Info.SysName := Path;
      Info.Vendor := VID;
      Info.Product := PID;
      Info.DevNodePath := '';
      Result.Add(Info);
    end;
  finally
    Names.Free;
    Reg.Free;
  end;
end;

function FindBySysName(const SysName: string): TUsbDeviceSysfsInfo;
var
  Filter: TEnumerateFilter;
  List: TList<TUsbDeviceSysfsInfo>;
  I: Integer;
begin
  Result := Default(TUsbDeviceSysfsInfo);
  Filter.Vendor := 0;
  SetLength(Filter.Products, 0);

  List := EnumerateUSBDevices(Filter);
  try
    for I := 0 to List.Count - 1 do
      if SameText(List[I].SysName, SysName) then
      begin
        Result := List[I];
        Exit;
      end;
  finally
    List.Free;
  end;
end;

end.
