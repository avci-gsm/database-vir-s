unit uOdinWire;

interface

uses
  SysUtils, uEndian;

const
  REQUEST_BOX_SIZE = 1024;
  DATA_INT_SIZE = 9;
  DATA_CHAR_SIZE = 128;
  MD5_SIZE = 32;

type
  TRqtCommandType = (
    rctEmpty = 0,
    rctInit = 100,
    rctPit = 101,
    rctXmit = 102,
    rctClose = 103
  );

  TRqtCommandParam = (
    // INIT
    rcpInitTarget = 0,
    rcpInitResetTime = 1,
    rcpInitTotalSize = 2,
    rcpInitOemState = 3,
    rcpInitNoOemState = 4,
    rcpInitPacketSize = 5,
    rcpInitXmitSize = 6,

    // PIT
    rcpPitSet = 0,
    rcpPitGet = 1,
    rcpPitStart = 2,
    rcpPitComplete = 3,

    // XMIT uncompressed
    rcpXmitDownload = 0,
    rcpXmitDump = 1,
    rcpXmitStart = 2,
    rcpXmitComplete = 3,
    rcpXmitSMD = 4,

    // XMIT compressed
    rcpXmitCompressedDownload = 5,
    rcpXmitCompressedStart = 6,
    rcpXmitCompressedComplete = 7,

    // CLOSE
    rcpCloseEnd = 0,
    rcpCloseReboot = 1,
    rcpCloseDisconnect = 2,
    rcpCloseRebootRecovery = 3
  );

  TProtocolVersion = (
    pvNone = 0,
    pvVer1 = 1,
    pvVer2 = 2,
    pvVer3 = 3,
    pvVer4 = 4,
    pvVer5 = 5
  );

  TResponseBox = packed record
    ID: Integer;
    Ack: Integer;
  end;

  TRequestBox = packed record
    ID: Integer;
    Data: Integer;
    IntData: array[0..DATA_INT_SIZE - 1] of Integer;
    CharData: array[0..DATA_CHAR_SIZE - 1] of ShortInt;
    MD5: array[0..MD5_SIZE - 1] of ShortInt;
    Dummy: array[0..REQUEST_BOX_SIZE - (2 * 4 + DATA_INT_SIZE * 4 + DATA_CHAR_SIZE + MD5_SIZE) - 1] of ShortInt;
  end;

procedure ResponseFromLE(var R: TResponseBox);
function MakeRequest(CmdType: TRqtCommandType; Param: TRqtCommandParam;
  const Ints: array of Integer; const Chars: array of ShortInt): TRequestBox; overload;
function MakeRequest(CmdType: TRqtCommandType; Param: TRqtCommandParam): TRequestBox; overload;

implementation

procedure ResponseFromLE(var R: TResponseBox);
begin
  R.ID := LEToHost32(R.ID);
  R.Ack := LEToHost32(R.Ack);
end;

function MakeRequest(CmdType: TRqtCommandType; Param: TRqtCommandParam;
  const Ints: array of Integer; const Chars: array of ShortInt): TRequestBox;
var
  I, N: Integer;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.ID := HostToLE32(Integer(CmdType));
  Result.Data := HostToLE32(Integer(Param));

  N := Length(Ints);
  if N > DATA_INT_SIZE then N := DATA_INT_SIZE;
  for I := 0 to N - 1 do
    Result.IntData[I] := HostToLE32(Ints[I]);

  N := Length(Chars);
  if N > DATA_CHAR_SIZE then N := DATA_CHAR_SIZE;
  for I := 0 to N - 1 do
    Result.CharData[I] := Chars[I];
end;

function MakeRequest(CmdType: TRqtCommandType; Param: TRqtCommandParam): TRequestBox;
begin
  Result := MakeRequest(CmdType, Param, [], []);
end;

end.
