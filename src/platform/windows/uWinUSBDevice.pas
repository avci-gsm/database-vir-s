unit uWinUSBDevice;

interface

uses
  SysUtils, Windows, uStatus;

const
  SAMSUNG_VID = $04E8;
  ODIN_PIDS: array[0..2] of Word = ($6601, $685D, $68C3);

type
  TUsbIds = record
    Vendor: Word;
    Product: Word;
  end;

  TUsbEndpoints = record
    BulkIn: Byte;
    BulkOut: Byte;
    BulkInMaxPacket: Word;
    BulkOutMaxPacket: Word;
  end;

  TWinUSBDevice = class
  private
    FDevNode: string;
    FHandle: THandle;
    FWinUSBHandle: THandle;
    FIds: TUsbIds;
    FEndpoints: TUsbEndpoints;
    FIfcNum: Integer;
  public
    constructor Create(const ADevNode: string);
    destructor Destroy; override;

    function OpenAndInit: TBrokkrStatus;
    procedure Close;

    function IsOpen: Boolean;

    property DevNode: string read FDevNode;
    property Handle: THandle read FHandle;
    property WinUSBHandle: THandle read FWinUSBHandle;
    property Ids: TUsbIds read FIds;
    property Endpoints: TUsbEndpoints read FEndpoints;
    property InterfaceNumber: Integer read FIfcNum;
  end;

implementation

{ TWinUSBDevice }

constructor TWinUSBDevice.Create(const ADevNode: string);
begin
  inherited Create;
  FDevNode := ADevNode;
  FHandle := INVALID_HANDLE_VALUE;
  FWinUSBHandle := 0;
  FIfcNum := -1;
  FillChar(FIds, SizeOf(FIds), 0);
  FillChar(FEndpoints, SizeOf(FEndpoints), 0);
end;

destructor TWinUSBDevice.Destroy;
begin
  Close;
  inherited;
end;

function TWinUSBDevice.OpenAndInit: TBrokkrStatus;
begin
  FHandle := CreateFile(
    PChar(FDevNode),
    GENERIC_READ or GENERIC_WRITE,
    FILE_SHARE_READ or FILE_SHARE_WRITE,
    nil,
    OPEN_EXISTING,
    FILE_FLAG_OVERLAPPED,
    0
  );

  if FHandle = INVALID_HANDLE_VALUE then
    Exit(TBrokkrStatus.Fail('Cannot open USB device: ' + SysErrorMessage(GetLastError)));

  Result := TBrokkrStatus.OK;
end;

procedure TWinUSBDevice.Close;
begin
  if FWinUSBHandle <> 0 then
  begin
    FWinUSBHandle := 0;
  end;

  if FHandle <> INVALID_HANDLE_VALUE then
  begin
    CloseHandle(FHandle);
    FHandle := INVALID_HANDLE_VALUE;
  end;
end;

function TWinUSBDevice.IsOpen: Boolean;
begin
  Result := FHandle <> INVALID_HANDLE_VALUE;
end;

end.
