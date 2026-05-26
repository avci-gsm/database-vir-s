unit uPit;

interface

uses
  SysUtils, Generics.Collections, uStatus, uEndian;

const
  PIT_MAGIC = $12349876;

type
  TPitHeaderWire = packed record
    Magic: Integer;
    Count: Integer;
    ComTar2: array[0..7] of ShortInt;
    CpuBlId: array[0..7] of ShortInt;
    LUCount: Word;
    Reserved: Word;
  end;

  TPartitionInfoWire = packed record
    BinType: Integer;
    DevType: Integer;
    ID: Integer;
    Attribute: Integer;
    UpdateAttribute: Integer;
    BlockSize: Integer;
    BlockLength: Integer;
    Offset: Integer;
    FileSize: Integer;
    Name: array[0..31] of ShortInt;
    FileName: array[0..31] of ShortInt;
    DeltaName: array[0..31] of ShortInt;
  end;

  TPartition = record
    ID: Integer;
    DevType: Integer;
    BeginBlock: Integer;
    BlockBytes: Integer;
    BlockSize: Integer;
    FileSize: UInt64;
    Name: string;
    FileName: string;
  end;

  TPitTable = class
  private
    FPartitions: TList<TPartition>;
    FComTar2: string;
    FCpuBlId: string;
    FLUCount: Word;
  public
    constructor Create;
    destructor Destroy; override;

    function FindByFileName(const BaseName: string): Integer;
    function CommonBlockSize: Integer;

    property Partitions: TList<TPartition> read FPartitions;
    property ComTar2: string read FComTar2 write FComTar2;
    property CpuBlId: string read FCpuBlId write FCpuBlId;
    property LUCount: Word read FLUCount write FLUCount;
  end;

function ParsePit(const Data: TBytes): TBrokkrResult<TPitTable>;

implementation

uses
  Math;

function TrimNulString(P: PShortInt; Len: Integer): string;
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

function TrimFixedField(P: PShortInt; Len: Integer): string;
begin
  Result := TrimNulString(P, Len);
  while (Length(Result) > 0) and (Result[Length(Result)] in [' ', #9, #13, #10]) do
    Delete(Result, Length(Result), 1);
end;

function BlockBytesForDevType(DevType: Integer): Integer;
begin
  if DevType = 8 then
    Result := 4096
  else
    Result := 512;
end;

{ TPitTable }

constructor TPitTable.Create;
begin
  inherited;
  FPartitions := TList<TPartition>.Create;
end;

destructor TPitTable.Destroy;
begin
  FPartitions.Free;
  inherited;
end;

function TPitTable.FindByFileName(const BaseName: string): Integer;
var
  I: Integer;
  P: TPartition;
begin
  for I := 0 to FPartitions.Count - 1 do
  begin
    P := FPartitions[I];
    if SameText(P.FileName, BaseName) then
      Exit(I);
  end;
  Result := -1;
end;

function TPitTable.CommonBlockSize: Integer;
var
  I: Integer;
  BS: Integer;
begin
  if FPartitions.Count = 0 then
    Exit(-1);
  BS := FPartitions[0].BlockSize;
  for I := 1 to FPartitions.Count - 1 do
    if FPartitions[I].BlockSize <> BS then
      Exit(-1);
  Result := BS;
end;

{ ParsePit }

function ParsePit(const Data: TBytes): TBrokkrResult<TPitTable>;
var
  Hdr: TPitHeaderWire;
  W: TPartitionInfoWire;
  Table: TPitTable;
  I: Integer;
  Count: Integer;
  Off: Integer;
  Required: Integer;
  P: TPartition;
  MaxBlockSize, MaxOffset: Integer;
  BlockSizeIsBeginBlock: Boolean;
begin
  if Length(Data) < SizeOf(TPitHeaderWire) then
    Exit(TBrokkrResult<TPitTable>.Fail('PIT parse: buffer too small for header'));

  Move(Data[0], Hdr, SizeOf(Hdr));
  Hdr.Magic := LEToHost32(Hdr.Magic);
  Hdr.Count := LEToHost32(Hdr.Count);
  Hdr.LUCount := LEToHost16(Hdr.LUCount);
  Hdr.Reserved := LEToHost16(Hdr.Reserved);

  if Hdr.Magic <> PIT_MAGIC then
    Exit(TBrokkrResult<TPitTable>.Fail('PIT parse: bad magic'));
  if Hdr.Count < 0 then
    Exit(TBrokkrResult<TPitTable>.Fail('PIT parse: negative partition count'));

  Count := Hdr.Count;
  Required := SizeOf(TPitHeaderWire) + Count * SizeOf(TPartitionInfoWire);
  if Length(Data) < Required then
    Exit(TBrokkrResult<TPitTable>.Fail('PIT parse: buffer too small'));

  Table := TPitTable.Create;
  Table.FComTar2 := TrimFixedField(@Hdr.ComTar2[0], 8);
  Table.FCpuBlId := TrimFixedField(@Hdr.CpuBlId[0], 8);
  Table.FLUCount := Hdr.LUCount;

  MaxBlockSize := 0;
  MaxOffset := 0;

  Off := SizeOf(TPitHeaderWire);
  for I := 0 to Count - 1 do
  begin
    Move(Data[Off], W, SizeOf(W));
    Inc(Off, SizeOf(W));

    W.BinType := LEToHost32(W.BinType);
    W.DevType := LEToHost32(W.DevType);
    W.ID := LEToHost32(W.ID);
    W.Attribute := LEToHost32(W.Attribute);
    W.UpdateAttribute := LEToHost32(W.UpdateAttribute);
    W.BlockSize := LEToHost32(W.BlockSize);
    W.BlockLength := LEToHost32(W.BlockLength);
    W.Offset := LEToHost32(W.Offset);
    W.FileSize := LEToHost32(W.FileSize);

    if W.BlockSize > MaxBlockSize then MaxBlockSize := W.BlockSize;
    if W.Offset > MaxOffset then MaxOffset := W.Offset;

    P.ID := W.ID;
    P.DevType := W.DevType;
    P.BlockBytes := BlockBytesForDevType(W.DevType);
    P.BlockSize := W.BlockSize;
    P.Name := TrimNulString(@W.Name[0], 32);
    P.FileName := TrimNulString(@W.FileName[0], 32);
    P.FileSize := 0;

    Table.FPartitions.Add(P);
  end;

  BlockSizeIsBeginBlock := (MaxBlockSize > 4096) and (MaxOffset <= 4096);
  for I := 0 to Table.FPartitions.Count - 1 do
  begin
    P := Table.FPartitions[I];
    // Re-read from raw to get offsets
    Move(Data[SizeOf(TPitHeaderWire) + I * SizeOf(TPartitionInfoWire)], W, SizeOf(W));
    W.BlockSize := LEToHost32(W.BlockSize);
    W.Offset := LEToHost32(W.Offset);

    if BlockSizeIsBeginBlock then
      P.BeginBlock := W.BlockSize
    else
      P.BeginBlock := W.Offset;

    Table.FPartitions[I] := P;
  end;

  Result := TBrokkrResult<TPitTable>.OK(Table);
end;

end.
