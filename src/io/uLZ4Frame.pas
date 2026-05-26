unit uLZ4Frame;

interface

uses
  SysUtils, Classes, uStatus, uByteSource;

const
  LZ4_ONE_MIB = 1024 * 1024;
  LZ4_MAGIC: Cardinal = $184D2204;

type
  TLZ4FrameHeaderInfo = record
    ContentSize: UInt64;
    FLG: Byte;
    BD: Byte;
    BlockIndependence: Boolean;
    BlockChecksum: Boolean;
    ContentChecksum: Boolean;
    HasContentSize: Boolean;
    HasDictID: Boolean;
    MaxBlockSize: Cardinal;
    HeaderBytes: Cardinal;
  end;

function ParseLZ4FrameHeader(Src: TByteSource): TBrokkrResult<TLZ4FrameHeaderInfo>;
function IsLZ4Name(const BaseName: string): Boolean;
function StripLZ4Suffix(const S: string): string;

implementation

function MaxBlockSizeFromBD(BD: Byte): Cardinal;
var
  ID: Byte;
begin
  ID := (BD shr 4) and $07;
  case ID of
    4: Result := 64 * 1024;
    5: Result := 256 * 1024;
    6: Result := 1024 * 1024;
    7: Result := 4 * 1024 * 1024;
  else
    Result := 0;
  end;
end;

function ReadExact(Src: TByteSource; var Buf: TBytes; Count: Integer): TBrokkrStatus;
var
  Done, Got: Integer;
begin
  SetLength(Buf, Count);
  Done := 0;
  while Done < Count do
  begin
    Got := Src.Read(Buf, Done, Count - Done);
    if Got <= 0 then
      Exit(TBrokkrStatus.Fail('LZ4: short read'));
    Inc(Done, Got);
  end;
  Result := TBrokkrStatus.OK;
end;

function ParseLZ4FrameHeader(Src: TByteSource): TBrokkrResult<TLZ4FrameHeaderInfo>;
var
  Info: TLZ4FrameHeaderInfo;
  Buf: TBytes;
  St: TBrokkrStatus;
  Magic: Cardinal;
  Version: Byte;
  I: Integer;
begin
  FillChar(Info, SizeOf(Info), 0);

  St := ReadExact(Src, Buf, 4);
  if not St.IsOK then
    Exit(TBrokkrResult<TLZ4FrameHeaderInfo>.Fail(St.Error));

  Magic := Cardinal(Buf[0]) or (Cardinal(Buf[1]) shl 8) or
           (Cardinal(Buf[2]) shl 16) or (Cardinal(Buf[3]) shl 24);
  if Magic <> LZ4_MAGIC then
    Exit(TBrokkrResult<TLZ4FrameHeaderInfo>.Fail('LZ4: bad magic'));

  St := ReadExact(Src, Buf, 2);
  if not St.IsOK then
    Exit(TBrokkrResult<TLZ4FrameHeaderInfo>.Fail(St.Error));

  Info.FLG := Buf[0];
  Info.BD := Buf[1];

  Version := (Info.FLG shr 6) and $03;
  if Version <> 1 then
    Exit(TBrokkrResult<TLZ4FrameHeaderInfo>.Fail('LZ4: unsupported frame version'));

  Info.BlockIndependence := (Info.FLG and $20) <> 0;
  Info.BlockChecksum := (Info.FLG and $10) <> 0;
  Info.HasContentSize := (Info.FLG and $08) <> 0;
  Info.ContentChecksum := (Info.FLG and $04) <> 0;
  Info.HasDictID := (Info.FLG and $01) <> 0;

  if not Info.BlockIndependence then
    Exit(TBrokkrResult<TLZ4FrameHeaderInfo>.Fail('LZ4: frame must use independent blocks'));
  if Info.BlockChecksum then
    Exit(TBrokkrResult<TLZ4FrameHeaderInfo>.Fail('LZ4: block checksum not supported'));
  if Info.HasDictID then
    Exit(TBrokkrResult<TLZ4FrameHeaderInfo>.Fail('LZ4: dictionary ID not supported'));
  if not Info.HasContentSize then
    Exit(TBrokkrResult<TLZ4FrameHeaderInfo>.Fail('LZ4: content size missing'));

  Info.MaxBlockSize := MaxBlockSizeFromBD(Info.BD);
  if Info.MaxBlockSize = 0 then
    Exit(TBrokkrResult<TLZ4FrameHeaderInfo>.Fail('LZ4: invalid max block size'));
  if Info.MaxBlockSize > LZ4_ONE_MIB then
    Exit(TBrokkrResult<TLZ4FrameHeaderInfo>.Fail('LZ4: max block size > 1MiB not supported'));

  St := ReadExact(Src, Buf, 8);
  if not St.IsOK then
    Exit(TBrokkrResult<TLZ4FrameHeaderInfo>.Fail(St.Error));

  Info.ContentSize := 0;
  for I := 7 downto 0 do
    Info.ContentSize := (Info.ContentSize shl 8) or UInt64(Buf[I]);

  if (Info.ContentSize > LZ4_ONE_MIB) and (Info.MaxBlockSize <> LZ4_ONE_MIB) then
    Exit(TBrokkrResult<TLZ4FrameHeaderInfo>.Fail('LZ4: content > 1MiB requires 1MiB blocks'));

  St := ReadExact(Src, Buf, 1);
  if not St.IsOK then
    Exit(TBrokkrResult<TLZ4FrameHeaderInfo>.Fail(St.Error));

  Info.HeaderBytes := 4 + 1 + 1 + 8 + 1;
  Result := TBrokkrResult<TLZ4FrameHeaderInfo>.OK(Info);
end;

function IsLZ4Name(const BaseName: string): Boolean;
begin
  Result := BaseName.EndsWith('.lz4', True);
end;

function StripLZ4Suffix(const S: string): string;
begin
  if (Length(S) >= 4) and S.EndsWith('.lz4', True) then
    Result := Copy(S, 1, Length(S) - 4)
  else
    Result := S;
end;

end.
