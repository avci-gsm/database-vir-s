unit uWinUSBConn;

interface

uses
  SysUtils, Windows, uStatus, uByteTransport, uWinUSBDevice;

type
  TWinUSBConnection = class(TInterfacedObject, IByteTransport)
  private
    FDev: TWinUSBDevice;
    FConnected: Boolean;
    FTimeoutMs: Integer;
    FMaxPackSize: NativeUInt;
  public
    constructor Create(ADev: TWinUSBDevice);

    function Open: TBrokkrStatus;
    procedure Close;

    function GetKind: TTransportKind;
    function GetConnected: Boolean;
    function GetTimeoutMs: Integer;
    procedure SetTimeoutMs(Value: Integer);
    procedure SetPacketSizeHint(Bytes: NativeUInt);

    function Send(const Data: TBytes; Retries: Cardinal = 8): Integer;
    function Recv(var Data: TBytes; Count: Integer; Retries: Cardinal = 8): Integer;
    function RecvZLP(Retries: Cardinal = 0): Integer;
  end;

implementation

{ TWinUSBConnection }

constructor TWinUSBConnection.Create(ADev: TWinUSBDevice);
begin
  inherited Create;
  FDev := ADev;
  FConnected := False;
  FTimeoutMs := 1000;
  FMaxPackSize := 1024 * 1024;
end;

function TWinUSBConnection.Open: TBrokkrStatus;
var
  St: TBrokkrStatus;
begin
  St := FDev.OpenAndInit;
  if not St.IsOK then
    Exit(St);
  FConnected := True;
  Result := TBrokkrStatus.OK;
end;

procedure TWinUSBConnection.Close;
begin
  FConnected := False;
  FDev.Close;
end;

function TWinUSBConnection.GetKind: TTransportKind;
begin
  Result := tkUsbBulk;
end;

function TWinUSBConnection.GetConnected: Boolean;
begin
  Result := FConnected;
end;

function TWinUSBConnection.GetTimeoutMs: Integer;
begin
  Result := FTimeoutMs;
end;

procedure TWinUSBConnection.SetTimeoutMs(Value: Integer);
begin
  FTimeoutMs := Value;
end;

procedure TWinUSBConnection.SetPacketSizeHint(Bytes: NativeUInt);
begin
  FMaxPackSize := Bytes;
end;

function TWinUSBConnection.Send(const Data: TBytes; Retries: Cardinal): Integer;
var
  Len: Integer;
  BytesWritten: DWORD;
  Overlapped: TOverlapped;
  OK: Boolean;
begin
  if not FConnected then Exit(-1);

  Len := Length(Data);
  FillChar(Overlapped, SizeOf(Overlapped), 0);
  Overlapped.hEvent := CreateEvent(nil, True, False, nil);
  try
    OK := WriteFile(FDev.Handle, Data[0], DWORD(Len), BytesWritten, @Overlapped);
    if not OK then
    begin
      if GetLastError = ERROR_IO_PENDING then
      begin
        WaitForSingleObject(Overlapped.hEvent, DWORD(FTimeoutMs));
        GetOverlappedResult(FDev.Handle, Overlapped, BytesWritten, False);
      end
      else
        Exit(-1);
    end;
    Result := Integer(BytesWritten);
  finally
    CloseHandle(Overlapped.hEvent);
  end;
end;

function TWinUSBConnection.Recv(var Data: TBytes; Count: Integer; Retries: Cardinal): Integer;
var
  BytesRead: DWORD;
  Overlapped: TOverlapped;
  OK: Boolean;
begin
  if not FConnected then Exit(-1);

  if Length(Data) < Count then
    SetLength(Data, Count);

  FillChar(Overlapped, SizeOf(Overlapped), 0);
  Overlapped.hEvent := CreateEvent(nil, True, False, nil);
  try
    OK := ReadFile(FDev.Handle, Data[0], DWORD(Count), BytesRead, @Overlapped);
    if not OK then
    begin
      if GetLastError = ERROR_IO_PENDING then
      begin
        WaitForSingleObject(Overlapped.hEvent, DWORD(FTimeoutMs));
        GetOverlappedResult(FDev.Handle, Overlapped, BytesRead, False);
      end
      else
        Exit(-1);
    end;
    Result := Integer(BytesRead);
  finally
    CloseHandle(Overlapped.hEvent);
  end;
end;

function TWinUSBConnection.RecvZLP(Retries: Cardinal): Integer;
var
  Dummy: TBytes;
begin
  SetLength(Dummy, 0);
  Result := Recv(Dummy, 0, Retries);
end;

end.
