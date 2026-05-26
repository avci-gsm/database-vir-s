unit uPitTransfer;

interface

uses
  SysUtils, uStatus, uOdinCmd, uPit;

function DownloadPitBytes(Odin: TOdinCommands; Retries: Cardinal = 8): TBrokkrResult<TBytes>;
function DownloadPitTable(Odin: TOdinCommands; Retries: Cardinal = 8): TBrokkrResult<TPitTable>;

implementation

function DownloadPitBytes(Odin: TOdinCommands; Retries: Cardinal): TBrokkrResult<TBytes>;
var
  SzResult: TBrokkrResult<Integer>;
  Sz: Integer;
  Buf: TBytes;
  St: TBrokkrStatus;
begin
  SzResult := Odin.GetPitSize(Retries);
  if not SzResult.IsOK then
    Exit(TBrokkrResult<TBytes>.Fail(SzResult.Error));

  Sz := SzResult.Value;
  if Sz <= 0 then
    Exit(TBrokkrResult<TBytes>.Fail('Device returned invalid PIT size'));

  SetLength(Buf, Sz);
  St := Odin.GetPit(Buf, Retries);
  if not St.IsOK then
    Exit(TBrokkrResult<TBytes>.Fail(St.Error));

  Result := TBrokkrResult<TBytes>.OK(Buf);
end;

function DownloadPitTable(Odin: TOdinCommands; Retries: Cardinal): TBrokkrResult<TPitTable>;
var
  BytesResult: TBrokkrResult<TBytes>;
  TableResult: TBrokkrResult<TPitTable>;
begin
  BytesResult := DownloadPitBytes(Odin, Retries);
  if not BytesResult.IsOK then
    Exit(TBrokkrResult<TPitTable>.Fail(BytesResult.Error));

  TableResult := ParsePit(BytesResult.Value);
  if not TableResult.IsOK then
    Exit(TBrokkrResult<TPitTable>.Fail(TableResult.Error));

  Result := TBrokkrResult<TPitTable>.OK(TableResult.Value);
end;

end.
