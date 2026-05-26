unit uByteSource;

interface

uses
  SysUtils, Classes, uStatus;

type
  TByteSource = class abstract
  public
    function DisplayName: string; virtual; abstract;
    function Size: UInt64; virtual; abstract;
    function Read(var Buf: TBytes; Offset, Count: Integer): Integer; virtual; abstract;
    function Status: TBrokkrStatus; virtual;
  end;

  TRawFileSource = class(TByteSource)
  private
    FPath: string;
    FStream: TFileStream;
    FSize: UInt64;
  public
    constructor Create(const APath: string);
    destructor Destroy; override;

    function DisplayName: string; override;
    function Size: UInt64; override;
    function Read(var Buf: TBytes; Offset, Count: Integer): Integer; override;
  end;

  TTarEntrySource = class(TByteSource)
  private
    FTarPath: string;
    FEntryName: string;
    FDataOffset: UInt64;
    FEntrySize: UInt64;
    FStream: TFileStream;
    FBytesRead: UInt64;
  public
    constructor Create(const ATarPath, AEntryName: string; ADataOffset, AEntrySize: UInt64);
    destructor Destroy; override;

    function DisplayName: string; override;
    function Size: UInt64; override;
    function Read(var Buf: TBytes; Offset, Count: Integer): Integer; override;
  end;

function OpenRawFile(const Path: string): TBrokkrResult<TByteSource>;

implementation

{ TByteSource }

function TByteSource.Status: TBrokkrStatus;
begin
  Result := TBrokkrStatus.OK;
end;

{ TRawFileSource }

constructor TRawFileSource.Create(const APath: string);
begin
  inherited Create;
  FPath := APath;
  FStream := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
  FSize := FStream.Size;
end;

destructor TRawFileSource.Destroy;
begin
  FStream.Free;
  inherited;
end;

function TRawFileSource.DisplayName: string;
begin
  Result := ExtractFileName(FPath);
end;

function TRawFileSource.Size: UInt64;
begin
  Result := FSize;
end;

function TRawFileSource.Read(var Buf: TBytes; Offset, Count: Integer): Integer;
begin
  Result := FStream.Read(Buf[Offset], Count);
end;

{ TTarEntrySource }

constructor TTarEntrySource.Create(const ATarPath, AEntryName: string;
  ADataOffset, AEntrySize: UInt64);
begin
  inherited Create;
  FTarPath := ATarPath;
  FEntryName := AEntryName;
  FDataOffset := ADataOffset;
  FEntrySize := AEntrySize;
  FBytesRead := 0;
  FStream := TFileStream.Create(ATarPath, fmOpenRead or fmShareDenyNone);
  FStream.Position := Int64(ADataOffset);
end;

destructor TTarEntrySource.Destroy;
begin
  FStream.Free;
  inherited;
end;

function TTarEntrySource.DisplayName: string;
begin
  Result := FEntryName;
end;

function TTarEntrySource.Size: UInt64;
begin
  Result := FEntrySize;
end;

function TTarEntrySource.Read(var Buf: TBytes; Offset, Count: Integer): Integer;
var
  Remaining: UInt64;
  ToRead: Integer;
begin
  Remaining := FEntrySize - FBytesRead;
  if Remaining = 0 then
    Exit(0);
  ToRead := Count;
  if UInt64(ToRead) > Remaining then
    ToRead := Integer(Remaining);
  Result := FStream.Read(Buf[Offset], ToRead);
  Inc(FBytesRead, UInt64(Result));
end;

{ OpenRawFile }

function OpenRawFile(const Path: string): TBrokkrResult<TByteSource>;
begin
  try
    Result := TBrokkrResult<TByteSource>.OK(TRawFileSource.Create(Path));
  except
    on E: Exception do
      Result := TBrokkrResult<TByteSource>.Fail('Cannot open file: ' + E.Message);
  end;
end;

end.
