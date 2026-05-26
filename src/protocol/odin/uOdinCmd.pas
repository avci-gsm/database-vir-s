unit uOdinCmd;

interface

uses
  SysUtils, uStatus, uByteTransport, uOdinWire;

type
  TInitTargetInfo = record
    AckWord: Cardinal;
    function ProtoRaw: Word;
    function Protocol: TProtocolVersion;
    function SupportsCompressedDownload: Boolean;
  end;

  TShutdownMode = (smNoReboot, smReboot);

  TOdinCommands = class
  private
    FConn: IByteTransport;

    function RequireConnected: TBrokkrStatus;
    function CheckResp(ExpectedID: Integer; const R: TResponseBox; OutAck: PInteger): TBrokkrStatus;
    function RPC(CmdType: TRqtCommandType; Param: TRqtCommandParam;
      const Ints: array of Integer; OutAck: PInteger = nil;
      Retries: Cardinal = 8): TBrokkrResult<TResponseBox>;
  public
    constructor Create(AConn: IByteTransport);

    function Handshake(Retries: Cardinal = 8): TBrokkrStatus;
    function GetVersion(Retries: Cardinal = 8): TBrokkrResult<TInitTargetInfo>;

    function SetupTransferOptions(PacketSize: Integer; Retries: Cardinal = 8): TBrokkrStatus;
    function SendTotalSize(TotalSize: UInt64; Proto: TProtocolVersion; Retries: Cardinal = 8): TBrokkrStatus;

    function GetPitSize(Retries: Cardinal = 8): TBrokkrResult<Integer>;
    function GetPit(var OutBuf: TBytes; Retries: Cardinal = 8): TBrokkrStatus;
    function SetPit(const PitData: TBytes; Retries: Cardinal = 8): TBrokkrStatus;

    function BeginDownload(RoundedTotalSize: Integer; Retries: Cardinal = 8): TBrokkrStatus;
    function BeginDownloadCompressed(CompSize: Integer; Retries: Cardinal = 8): TBrokkrStatus;

    function EndDownload(SizeToFlash, PartID, DevType: Integer;
      IsLast: Boolean; BinType: Integer = 0; EfsClear: Boolean = False;
      BootUpdate: Boolean = False; Retries: Cardinal = 8): TBrokkrStatus;
    function EndDownloadCompressed(DecompSizeToFlash, PartID, DevType: Integer;
      IsLast: Boolean; BinType: Integer = 0; EfsClear: Boolean = False;
      BootUpdate: Boolean = False; Retries: Cardinal = 8): TBrokkrStatus;

    function Shutdown(Mode: TShutdownMode; Retries: Cardinal = 8): TBrokkrStatus;

    function SendRaw(const Data: TBytes; Retries: Cardinal = 8): TBrokkrStatus;
    function RecvRaw(var Data: TBytes; Count: Integer; Retries: Cardinal = 8): TBrokkrStatus;

    function SendRequest(const Rq: TRequestBox; Retries: Cardinal = 8): TBrokkrStatus;
    function RecvCheckedResponse(ExpectedID: Integer; OutAck: PInteger = nil;
      Retries: Cardinal = 8): TBrokkrResult<TResponseBox>;

    property Conn: IByteTransport read FConn;
  end;

implementation

const
  BOOTLOADER_FAIL = Integer($FFFFFFFF);

{ TInitTargetInfo }

function TInitTargetInfo.ProtoRaw: Word;
begin
  Result := Word((AckWord shr 16) and $FFFF);
end;

function TInitTargetInfo.Protocol: TProtocolVersion;
var
  P: Word;
begin
  P := ProtoRaw;
  if P = 0 then
    Result := pvVer1
  else if P <= Ord(High(TProtocolVersion)) then
    Result := TProtocolVersion(P)
  else
    Result := pvVer5;
end;

function TInitTargetInfo.SupportsCompressedDownload: Boolean;
begin
  Result := (AckWord and $8000) <> 0;
end;

{ TOdinCommands }

constructor TOdinCommands.Create(AConn: IByteTransport);
begin
  inherited Create;
  FConn := AConn;
end;

function TOdinCommands.RequireConnected: TBrokkrStatus;
begin
  if FConn.Connected then
    Result := TBrokkrStatus.OK
  else
    Result := TBrokkrStatus.Fail('Transport not connected');
end;

function TOdinCommands.CheckResp(ExpectedID: Integer; const R: TResponseBox; OutAck: PInteger): TBrokkrStatus;
begin
  if R.ID = BOOTLOADER_FAIL then
    Exit(TBrokkrStatus.Fail('Bootloader returned FAIL'));
  if R.ID = Low(Integer) then
    Exit(TBrokkrStatus.Fail('Invalid response id (INT_MIN)'));
  if R.ID <> ExpectedID then
    Exit(TBrokkrStatus.Fail('Unexpected response id'));

  if OutAck <> nil then
    OutAck^ := R.Ack
  else if R.Ack < 0 then
    Exit(TBrokkrStatus.Failf('Operation failed (%d)', [R.Ack]));

  Result := TBrokkrStatus.OK;
end;

function TOdinCommands.SendRaw(const Data: TBytes; Retries: Cardinal): TBrokkrStatus;
var
  St: TBrokkrStatus;
  Off, Sent, Len: Integer;
begin
  St := RequireConnected;
  if not St.IsOK then Exit(St);

  Len := Length(Data);
  Off := 0;
  while Off < Len do
  begin
    Sent := FConn.Send(Copy(Data, Off, Len - Off), Retries);
    if Sent <= 0 then
      Exit(TBrokkrStatus.Fail('Send failed'));
    Inc(Off, Sent);
  end;
  Result := TBrokkrStatus.OK;
end;

function TOdinCommands.RecvRaw(var Data: TBytes; Count: Integer; Retries: Cardinal): TBrokkrStatus;
var
  St: TBrokkrStatus;
  Off, Got: Integer;
begin
  St := RequireConnected;
  if not St.IsOK then Exit(St);

  SetLength(Data, Count);
  Off := 0;
  while Off < Count do
  begin
    Got := FConn.Recv(Data, Count - Off, Retries);
    if Got <= 0 then
      Exit(TBrokkrStatus.Fail('Receive failed'));
    Inc(Off, Got);
  end;
  Result := TBrokkrStatus.OK;
end;

function TOdinCommands.SendRequest(const Rq: TRequestBox; Retries: Cardinal): TBrokkrStatus;
var
  Data: TBytes;
begin
  SetLength(Data, SizeOf(Rq));
  Move(Rq, Data[0], SizeOf(Rq));
  Result := SendRaw(Data, Retries);
end;

function TOdinCommands.RecvCheckedResponse(ExpectedID: Integer; OutAck: PInteger;
  Retries: Cardinal): TBrokkrResult<TResponseBox>;
var
  R: TResponseBox;
  Data: TBytes;
  St: TBrokkrStatus;
begin
  St := RecvRaw(Data, SizeOf(R), Retries);
  if not St.IsOK then
    Exit(TBrokkrResult<TResponseBox>.Fail(St.Error));

  Move(Data[0], R, SizeOf(R));
  ResponseFromLE(R);

  St := CheckResp(ExpectedID, R, OutAck);
  if not St.IsOK then
    Exit(TBrokkrResult<TResponseBox>.Fail(St.Error));

  Result := TBrokkrResult<TResponseBox>.OK(R);
end;

function TOdinCommands.RPC(CmdType: TRqtCommandType; Param: TRqtCommandParam;
  const Ints: array of Integer; OutAck: PInteger; Retries: Cardinal): TBrokkrResult<TResponseBox>;
var
  St: TBrokkrStatus;
begin
  St := SendRequest(MakeRequest(CmdType, Param, Ints, []), Retries);
  if not St.IsOK then
    Exit(TBrokkrResult<TResponseBox>.Fail(St.Error));
  Result := RecvCheckedResponse(Integer(CmdType), OutAck, Retries);
end;

function TOdinCommands.Handshake(Retries: Cardinal): TBrokkrStatus;
var
  St: TBrokkrStatus;
  Ping, Resp: TBytes;
  Have, Got: Integer;
begin
  St := RequireConnected;
  if not St.IsOK then Exit(St);

  if FConn.Kind = tkUsbBulk then
    Ping := TBytes.Create(Ord('O'), Ord('D'), Ord('I'), Ord('N'), 0)
  else
    Ping := TBytes.Create(Ord('O'), Ord('D'), Ord('I'), Ord('N'));

  St := SendRaw(Ping, Retries);
  if not St.IsOK then Exit(St);

  SetLength(Resp, 64);
  Have := 0;
  while Have < 4 do
  begin
    Got := FConn.Recv(Resp, 64 - Have, Retries);
    if Got <= 0 then
      Exit(TBrokkrStatus.Fail('Handshake receive failed'));
    Inc(Have, Got);
  end;

  if (Resp[0] <> Ord('L')) or (Resp[1] <> Ord('O')) or
     (Resp[2] <> Ord('K')) or (Resp[3] <> Ord('E')) then
    Exit(TBrokkrStatus.Fail('Handshake failed (expected LOKE)'));

  Result := TBrokkrStatus.OK;
end;

function TOdinCommands.GetVersion(Retries: Cardinal): TBrokkrResult<TInitTargetInfo>;
var
  AckI32: Integer;
  R: TBrokkrResult<TResponseBox>;
  Info: TInitTargetInfo;
begin
  AckI32 := 0;
  R := RPC(rctInit, rcpInitTarget, [Integer(pvVer5)], @AckI32, Retries);
  if not R.IsOK then
    Exit(TBrokkrResult<TInitTargetInfo>.Fail(R.Error));

  Info.AckWord := Cardinal(AckI32);
  Result := TBrokkrResult<TInitTargetInfo>.OK(Info);
end;

function TOdinCommands.SetupTransferOptions(PacketSize: Integer; Retries: Cardinal): TBrokkrStatus;
var
  R: TBrokkrResult<TResponseBox>;
begin
  R := RPC(rctInit, rcpInitPacketSize, [PacketSize], nil, Retries);
  if not R.IsOK then
    Exit(TBrokkrStatus.Fail(R.Error));
  if PacketSize > 0 then
    FConn.SetPacketSizeHint(NativeUInt(Cardinal(PacketSize)));
  Result := TBrokkrStatus.OK;
end;

function TOdinCommands.SendTotalSize(TotalSize: UInt64; Proto: TProtocolVersion; Retries: Cardinal): TBrokkrStatus;
var
  R: TBrokkrResult<TResponseBox>;
  Lo, Hi: Integer;
begin
  if Proto <= pvVer1 then
  begin
    if TotalSize > Cardinal(MaxInt) then
      Exit(TBrokkrStatus.Fail('TOTALSIZE exceeds ODIN int32 limit on protocol v0/v1'));
    R := RPC(rctInit, rcpInitTotalSize, [Integer(TotalSize)], nil, Retries);
  end
  else
  begin
    Lo := Integer(Cardinal(TotalSize and $FFFFFFFF));
    Hi := Integer(Cardinal((TotalSize shr 32) and $FFFFFFFF));
    R := RPC(rctInit, rcpInitTotalSize, [Lo, Hi], nil, Retries);
  end;

  if not R.IsOK then
    Exit(TBrokkrStatus.Fail(R.Error));
  Result := TBrokkrStatus.OK;
end;

function TOdinCommands.GetPitSize(Retries: Cardinal): TBrokkrResult<Integer>;
var
  PitSize: Integer;
  R: TBrokkrResult<TResponseBox>;
begin
  PitSize := 0;
  R := RPC(rctPit, rcpPitGet, [], @PitSize, Retries);
  if not R.IsOK then
    Exit(TBrokkrResult<Integer>.Fail(R.Error));
  Result := TBrokkrResult<Integer>.OK(PitSize);
end;

function TOdinCommands.GetPit(var OutBuf: TBytes; Retries: Cardinal): TBrokkrStatus;
const
  PIT_TRANSMIT_UNIT = 500;
var
  PitSize, Parts, Idx: Integer;
  SizeToDownload, Off: Integer;
  PitIndex: Integer;
  St: TBrokkrStatus;
  ChunkBuf: TBytes;
  R: TBrokkrResult<TResponseBox>;
begin
  PitSize := Length(OutBuf);
  if PitSize = 0 then
    Exit(TBrokkrStatus.Fail('PIT output buffer empty'));

  Parts := ((PitSize - 1) div PIT_TRANSMIT_UNIT) + 1;

  for Idx := 0 to Parts - 1 do
  begin
    PitIndex := Idx;
    St := SendRequest(MakeRequest(rctPit, rcpPitStart, [PitIndex], []), Retries);
    if not St.IsOK then Exit(St);

    SizeToDownload := PIT_TRANSMIT_UNIT;
    if PitSize - (PIT_TRANSMIT_UNIT * Idx) < SizeToDownload then
      SizeToDownload := PitSize - (PIT_TRANSMIT_UNIT * Idx);
    Off := Idx * PIT_TRANSMIT_UNIT;

    St := RecvRaw(ChunkBuf, SizeToDownload, Retries);
    if not St.IsOK then Exit(St);

    Move(ChunkBuf[0], OutBuf[Off], SizeToDownload);
  end;

  FConn.RecvZLP;
  R := RPC(rctPit, rcpPitComplete, [], nil, Retries);
  if not R.IsOK then
    Exit(TBrokkrStatus.Fail(R.Error));

  Result := TBrokkrStatus.OK;
end;

function TOdinCommands.SetPit(const PitData: TBytes; Retries: Cardinal): TBrokkrStatus;
var
  R: TBrokkrResult<TResponseBox>;
begin
  if Length(PitData) = 0 then
    Exit(TBrokkrStatus.Fail('PIT buffer empty'));

  R := RPC(rctPit, rcpPitSet, [Length(PitData)], nil, Retries);
  if not R.IsOK then
    Exit(TBrokkrStatus.Fail(R.Error));

  Result := SendRaw(PitData, Retries);
  if not Result.IsOK then Exit;

  FConn.RecvZLP;
  R := RPC(rctPit, rcpPitComplete, [], nil, Retries);
  if not R.IsOK then
    Result := TBrokkrStatus.Fail(R.Error)
  else
    Result := TBrokkrStatus.OK;
end;

function TOdinCommands.BeginDownload(RoundedTotalSize: Integer; Retries: Cardinal): TBrokkrStatus;
var
  R: TBrokkrResult<TResponseBox>;
begin
  R := RPC(rctXmit, rcpXmitStart, [RoundedTotalSize], nil, Retries);
  if not R.IsOK then
    Exit(TBrokkrStatus.Fail(R.Error));
  Result := TBrokkrStatus.OK;
end;

function TOdinCommands.BeginDownloadCompressed(CompSize: Integer; Retries: Cardinal): TBrokkrStatus;
var
  R: TBrokkrResult<TResponseBox>;
begin
  R := RPC(rctXmit, rcpXmitCompressedStart, [CompSize], nil, Retries);
  if not R.IsOK then
    Exit(TBrokkrStatus.Fail(R.Error));
  Result := TBrokkrStatus.OK;
end;

function TOdinCommands.EndDownload(SizeToFlash, PartID, DevType: Integer;
  IsLast: Boolean; BinType: Integer; EfsClear, BootUpdate: Boolean;
  Retries: Cardinal): TBrokkrStatus;
var
  Ints: array[0..5] of Integer;
  R: TBrokkrResult<TResponseBox>;
begin
  Ints[0] := SizeToFlash;
  Ints[1] := 0;
  Ints[2] := DevType;
  Ints[3] := PartID;
  Ints[4] := BinType;
  if IsLast then
    Ints[5] := 1
  else
    Ints[5] := 0;

  R := RPC(rctXmit, rcpXmitComplete, Ints, nil, Retries);
  if not R.IsOK then
    Exit(TBrokkrStatus.Fail(R.Error));
  Result := TBrokkrStatus.OK;
end;

function TOdinCommands.EndDownloadCompressed(DecompSizeToFlash, PartID, DevType: Integer;
  IsLast: Boolean; BinType: Integer; EfsClear, BootUpdate: Boolean;
  Retries: Cardinal): TBrokkrStatus;
var
  Ints: array[0..5] of Integer;
  R: TBrokkrResult<TResponseBox>;
begin
  Ints[0] := DecompSizeToFlash;
  Ints[1] := 0;
  Ints[2] := DevType;
  Ints[3] := PartID;
  Ints[4] := BinType;
  if IsLast then
    Ints[5] := 1
  else
    Ints[5] := 0;

  R := RPC(rctXmit, rcpXmitCompressedComplete, Ints, nil, Retries);
  if not R.IsOK then
    Exit(TBrokkrStatus.Fail(R.Error));
  Result := TBrokkrStatus.OK;
end;

function TOdinCommands.Shutdown(Mode: TShutdownMode; Retries: Cardinal): TBrokkrStatus;
var
  Param: TRqtCommandParam;
  R: TBrokkrResult<TResponseBox>;
begin
  if Mode = smReboot then
    Param := rcpCloseReboot
  else
    Param := rcpCloseEnd;

  R := RPC(rctClose, Param, [], nil, Retries);
  if not R.IsOK then
    Exit(TBrokkrStatus.Fail(R.Error));
  Result := TBrokkrStatus.OK;
end;

end.
