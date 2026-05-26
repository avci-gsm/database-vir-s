unit uTar;

interface

uses
  SysUtils, Classes, Generics.Collections, uStatus;

type
  TTarEntry = record
    Name: string;
    Size: UInt64;
    DataOffset: UInt64;
  end;

  TTarArchive = class
  private
    FPath: string;
    FEntries: TList<TTarEntry>;
    FPayloadSizeBytes: UInt64;
    FHasPayloadSize: Boolean;
    FValidateChecksums: Boolean;

    class function ParseOctal(const S: AnsiString): UInt64; static;
    class function TrimCStr(P: PAnsiChar; Len: Integer): string; static;
    class function HeaderAllZero(const Header: array of Byte): Boolean; static;
    class function ValidateHeaderChecksum(const Header: array of Byte): Boolean; static;
    function Scan: TBrokkrStatus;
  public
    constructor Create;
    destructor Destroy; override;

    class function Open(const APath: string; ValidateChecksums: Boolean = True): TBrokkrResult<TTarArchive>; static;
    class function IsTarFile(const APath: string): Boolean; static;

    function FindByBasename(const Base: string): Integer;

    property Path: string read FPath;
    property Entries: TList<TTarEntry> read FEntries;
    property PayloadSizeBytes: UInt64 read FPayloadSizeBytes;
  end;

implementation

uses
  Math;

const
  TAR_BLOCK_SIZE = 512;

{ TTarArchive }

constructor TTarArchive.Create;
begin
  inherited;
  FEntries := TList<TTarEntry>.Create;
  FHasPayloadSize := False;
  FPayloadSizeBytes := 0;
end;

destructor TTarArchive.Destroy;
begin
  FEntries.Free;
  inherited;
end;

class function TTarArchive.ParseOctal(const S: AnsiString): UInt64;
var
  I: Integer;
  C: AnsiChar;
begin
  Result := 0;
  for I := 1 to Length(S) do
  begin
    C := S[I];
    if (C >= '0') and (C <= '7') then
      Result := (Result shl 3) or UInt64(Ord(C) - Ord('0'))
    else if (C = #0) or (C = ' ') then
      Break;
  end;
end;

class function TTarArchive.TrimCStr(P: PAnsiChar; Len: Integer): string;
var
  S: AnsiString;
  I: Integer;
begin
  SetLength(S, Len);
  Move(P^, S[1], Len);
  for I := 1 to Len do
  begin
    if S[I] = #0 then
    begin
      SetLength(S, I - 1);
      Break;
    end;
  end;
  Result := string(S);
end;

class function TTarArchive.HeaderAllZero(const Header: array of Byte): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(Header) do
    if Header[I] <> 0 then
      Exit(False);
  Result := True;
end;

class function TTarArchive.ValidateHeaderChecksum(const Header: array of Byte): Boolean;
var
  Stored, Computed: Cardinal;
  I: Integer;
  S: AnsiString;
begin
  SetLength(S, 8);
  Move(Header[148], S[1], 8);
  Stored := Cardinal(ParseOctal(S));

  Computed := 0;
  for I := 0 to 511 do
  begin
    if (I >= 148) and (I < 156) then
      Inc(Computed, Ord(' '))
    else
      Inc(Computed, Header[I]);
  end;

  Result := (Computed = Stored);
end;

class function TTarArchive.IsTarFile(const APath: string): Boolean;
var
  FS: TFileStream;
  Header: array[0..511] of Byte;
  Magic: AnsiString;
begin
  Result := False;
  if not FileExists(APath) then Exit;
  try
    FS := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
    try
      if FS.Size < 512 then Exit;
      FS.ReadBuffer(Header, 512);
      SetLength(Magic, 5);
      Move(Header[257], Magic[1], 5);
      Result := (Magic = 'ustar');
    finally
      FS.Free;
    end;
  except
    Result := False;
  end;
end;

function TTarArchive.Scan: TBrokkrStatus;
var
  FS: TFileStream;
  Header: array[0..511] of Byte;
  BytesRead: Integer;
  EntryName: string;
  EntrySize: UInt64;
  DataOffset: UInt64;
  SizeStr: AnsiString;
  Padding: UInt64;
  TypeFlag: AnsiChar;
  ZeroCount: Integer;
  Prefix, NameField: string;
  E: TTarEntry;
  K: Integer;
begin
  FEntries.Clear;
  FPayloadSizeBytes := 0;
  FHasPayloadSize := False;
  ZeroCount := 0;

  try
    FS := TFileStream.Create(FPath, fmOpenRead or fmShareDenyNone);
  except
    on Ex: Exception do
      Exit(TBrokkrStatus.Fail('Cannot open tar: ' + Ex.Message));
  end;

  try
    while FS.Position + TAR_BLOCK_SIZE <= FS.Size do
    begin
      BytesRead := FS.Read(Header, TAR_BLOCK_SIZE);
      if BytesRead < TAR_BLOCK_SIZE then
        Break;

      if HeaderAllZero(Header) then
      begin
        Inc(ZeroCount);
        if ZeroCount >= 2 then
          Break;
        Continue;
      end;
      ZeroCount := 0;

      if FValidateChecksums and not ValidateHeaderChecksum(Header) then
        Exit(TBrokkrStatus.Fail('TAR: bad header checksum'));

      TypeFlag := AnsiChar(Header[156]);

      NameField := TrimCStr(@Header[0], 100);
      Prefix := TrimCStr(@Header[345], 155);
      if Prefix <> '' then
        EntryName := Prefix + '/' + NameField
      else
        EntryName := NameField;

      SetLength(SizeStr, 12);
      Move(Header[124], SizeStr[1], 12);

      if (Byte(SizeStr[1]) and $80) <> 0 then
      begin
        EntrySize := 0;
        for K := 1 to 12 do
          EntrySize := (EntrySize shl 8) or Byte(SizeStr[K]);
        EntrySize := EntrySize and $7FFFFFFFFFFFFFFF;
      end
      else
        EntrySize := ParseOctal(SizeStr);

      DataOffset := UInt64(FS.Position);

      if (TypeFlag = '0') or (TypeFlag = #0) then
      begin
        E.Name := EntryName;
        E.Size := EntrySize;
        E.DataOffset := DataOffset;
        FEntries.Add(E);
        FPayloadSizeBytes := FPayloadSizeBytes + EntrySize;
        FHasPayloadSize := True;
      end;

      Padding := ((EntrySize + TAR_BLOCK_SIZE - 1) div TAR_BLOCK_SIZE) * TAR_BLOCK_SIZE;
      FS.Position := Int64(DataOffset) + Int64(Padding);
    end;
  finally
    FS.Free;
  end;

  Result := TBrokkrStatus.OK;
end;

class function TTarArchive.Open(const APath: string; ValidateChecksums: Boolean): TBrokkrResult<TTarArchive>;
var
  Arch: TTarArchive;
  St: TBrokkrStatus;
begin
  Arch := TTarArchive.Create;
  Arch.FPath := APath;
  Arch.FValidateChecksums := ValidateChecksums;
  St := Arch.Scan;
  if not St.IsOK then
  begin
    Arch.Free;
    Exit(TBrokkrResult<TTarArchive>.Fail(St.Error));
  end;
  Result := TBrokkrResult<TTarArchive>.OK(Arch);
end;

function TTarArchive.FindByBasename(const Base: string): Integer;
var
  I: Integer;
  E: TTarEntry;
  EntryBase: string;
begin
  for I := 0 to FEntries.Count - 1 do
  begin
    E := FEntries[I];
    EntryBase := ExtractFileName(StringReplace(E.Name, '/', '\', [rfReplaceAll]));
    if SameText(EntryBase, Base) then
      Exit(I);
  end;
  Result := -1;
end;

end.
