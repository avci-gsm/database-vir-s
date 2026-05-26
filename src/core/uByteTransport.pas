unit uByteTransport;

interface

uses
  SysUtils, uStatus;

type
  TTransportKind = (tkUsbBulk, tkTcpStream);

  IByteTransport = interface
    ['{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}']
    function GetKind: TTransportKind;
    function GetConnected: Boolean;
    function GetTimeoutMs: Integer;
    procedure SetTimeoutMs(Value: Integer);
    procedure SetPacketSizeHint(Bytes: NativeUInt);

    function Send(const Data: TBytes; Retries: Cardinal = 8): Integer;
    function Recv(var Data: TBytes; Count: Integer; Retries: Cardinal = 8): Integer;
    function RecvZLP(Retries: Cardinal = 0): Integer;

    property Kind: TTransportKind read GetKind;
    property Connected: Boolean read GetConnected;
    property TimeoutMs: Integer read GetTimeoutMs write SetTimeoutMs;
  end;

implementation

end.
