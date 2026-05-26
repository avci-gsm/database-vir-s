unit uTcpTransport;

interface

uses
  SysUtils, WinSock, uStatus, uByteTransport;

const
  WIRELESS_PORT = 13579;

type
  TTcpConnection = class(TInterfacedObject, IByteTransport)
  private
    FSocket: TSocket;
    FConnected: Boolean;
    FTimeoutMs: Integer;
  public
    constructor Create;
    destructor Destroy; override;

    function Listen(Port: Word): TBrokkrStatus;
    function Accept: TBrokkrStatus;
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

var
  WSAInitialized: Boolean = False;

procedure InitWSA;
var
  WSAData: TWSAData;
begin
  if not WSAInitialized then
  begin
    WSAStartup(MakeWord(2, 2), WSAData);
    WSAInitialized := True;
  end;
end;

{ TTcpConnection }

constructor TTcpConnection.Create;
begin
  inherited;
  InitWSA;
  FSocket := INVALID_SOCKET;
  FConnected := False;
  FTimeoutMs := 1000;
end;

destructor TTcpConnection.Destroy;
begin
  Close;
  inherited;
end;

function TTcpConnection.Listen(Port: Word): TBrokkrStatus;
var
  Addr: TSockAddrIn;
  ListenSock, ClientSock: TSocket;
  OptVal: Integer;
begin
  ListenSock := WinSock.socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
  if ListenSock = INVALID_SOCKET then
    Exit(TBrokkrStatus.Fail('Cannot create listen socket'));

  OptVal := 1;
  WinSock.setsockopt(ListenSock, SOL_SOCKET, SO_REUSEADDR, @OptVal, SizeOf(OptVal));

  FillChar(Addr, SizeOf(Addr), 0);
  Addr.sin_family := AF_INET;
  Addr.sin_port := WinSock.htons(Port);
  Addr.sin_addr.S_addr := INADDR_ANY;

  if WinSock.bind(ListenSock, Addr, SizeOf(Addr)) = SOCKET_ERROR then
  begin
    WinSock.closesocket(ListenSock);
    Exit(TBrokkrStatus.Fail('Bind failed'));
  end;

  if WinSock.listen(ListenSock, 1) = SOCKET_ERROR then
  begin
    WinSock.closesocket(ListenSock);
    Exit(TBrokkrStatus.Fail('Listen failed'));
  end;

  ClientSock := WinSock.accept(ListenSock, nil, nil);
  WinSock.closesocket(ListenSock);

  if ClientSock = INVALID_SOCKET then
    Exit(TBrokkrStatus.Fail('Accept failed'));

  FSocket := ClientSock;
  FConnected := True;
  Result := TBrokkrStatus.OK;
end;

function TTcpConnection.Accept: TBrokkrStatus;
begin
  Result := Listen(WIRELESS_PORT);
end;

procedure TTcpConnection.Close;
begin
  if FSocket <> INVALID_SOCKET then
  begin
    WinSock.closesocket(FSocket);
    FSocket := INVALID_SOCKET;
  end;
  FConnected := False;
end;

function TTcpConnection.GetKind: TTransportKind;
begin
  Result := tkTcpStream;
end;

function TTcpConnection.GetConnected: Boolean;
begin
  Result := FConnected;
end;

function TTcpConnection.GetTimeoutMs: Integer;
begin
  Result := FTimeoutMs;
end;

procedure TTcpConnection.SetTimeoutMs(Value: Integer);
begin
  FTimeoutMs := Value;
  if FSocket <> INVALID_SOCKET then
  begin
    WinSock.setsockopt(FSocket, SOL_SOCKET, SO_RCVTIMEO, @Value, SizeOf(Value));
    WinSock.setsockopt(FSocket, SOL_SOCKET, SO_SNDTIMEO, @Value, SizeOf(Value));
  end;
end;

procedure TTcpConnection.SetPacketSizeHint(Bytes: NativeUInt);
begin
  // TCP doesn't use packet size hint
end;

function TTcpConnection.Send(const Data: TBytes; Retries: Cardinal): Integer;
var
  Len: Integer;
begin
  if not FConnected then Exit(-1);
  Len := Length(Data);
  Result := WinSock.send(FSocket, Data[0], Len, 0);
end;

function TTcpConnection.Recv(var Data: TBytes; Count: Integer; Retries: Cardinal): Integer;
begin
  if not FConnected then Exit(-1);
  if Length(Data) < Count then
    SetLength(Data, Count);
  Result := WinSock.recv(FSocket, Data[0], Count, 0);
end;

function TTcpConnection.RecvZLP(Retries: Cardinal): Integer;
begin
  Result := 0;
end;

end.
