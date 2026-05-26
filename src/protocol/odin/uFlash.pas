unit uFlash;

interface

uses
  SysUtils, Classes, Generics.Collections, uStatus, uByteSource, uTar, uPit,
  uLZ4Frame;

type
  TImageKind = (ikRawFile, ikTarEntry);

  TImageSpec = record
    Kind: TImageKind;
    Path: string;
    EntryName: string;
    EntryDataOffset: UInt64;
    EntryDiskSize: UInt64;

    BaseName: string;
    SourceBaseName: string;
    Size: UInt64;
    DiskSize: UInt64;
    IsLZ4: Boolean;
    Display: string;

    function Open: TBrokkrResult<TByteSource>;
  end;

  TFlashItem = record
    Part: TPartition;
    Spec: TImageSpec;
  end;

function ExpandInputsTarOrRaw(const Inputs: TStringList): TBrokkrResult<TList<TImageSpec>>;
function MapToPit(PitTable: TPitTable; Sources: TList<TImageSpec>): TBrokkrResult<TList<TFlashItem>>;

implementation

{ TImageSpec }

function TImageSpec.Open: TBrokkrResult<TByteSource>;
begin
  case Kind of
    ikRawFile:
      begin
        try
          Result := TBrokkrResult<TByteSource>.OK(TRawFileSource.Create(Path));
        except
          on E: Exception do
            Result := TBrokkrResult<TByteSource>.Fail('Cannot open: ' + E.Message);
        end;
      end;
    ikTarEntry:
      begin
        try
          Result := TBrokkrResult<TByteSource>.OK(
            TTarEntrySource.Create(Path, EntryName, EntryDataOffset, EntryDiskSize));
        except
          on E: Exception do
            Result := TBrokkrResult<TByteSource>.Fail('Cannot open tar entry: ' + E.Message);
        end;
      end;
  else
    Result := TBrokkrResult<TByteSource>.Fail('ImageSpec: invalid kind');
  end;
end;

function MakeSpecFromFile(const FilePath: string): TBrokkrResult<TImageSpec>;
var
  Spec: TImageSpec;
  Src: TByteSource;
  R: TBrokkrResult<TByteSource>;
  LZ4R: TBrokkrResult<TLZ4FrameHeaderInfo>;
begin
  FillChar(Spec, SizeOf(Spec), 0);
  Spec.Kind := ikRawFile;
  Spec.Path := FilePath;
  Spec.SourceBaseName := ExtractFileName(FilePath);
  Spec.IsLZ4 := IsLZ4Name(Spec.SourceBaseName);

  if Spec.IsLZ4 then
    Spec.BaseName := StripLZ4Suffix(Spec.SourceBaseName)
  else
    Spec.BaseName := Spec.SourceBaseName;

  Spec.Display := Spec.SourceBaseName;

  R := OpenRawFile(FilePath);
  if not R.IsOK then
    Exit(TBrokkrResult<TImageSpec>.Fail(R.Error));

  Src := R.Value;
  try
    Spec.DiskSize := Src.Size;
    if Spec.IsLZ4 then
    begin
      LZ4R := ParseLZ4FrameHeader(Src);
      if not LZ4R.IsOK then
        Exit(TBrokkrResult<TImageSpec>.Fail(LZ4R.Error));
      Spec.Size := LZ4R.Value.ContentSize;
    end
    else
      Spec.Size := Spec.DiskSize;
  finally
    Src.Free;
  end;

  Result := TBrokkrResult<TImageSpec>.OK(Spec);
end;

function MakeSpecFromTarEntry(const TarPath: string; const E: TTarEntry): TBrokkrResult<TImageSpec>;
var
  Spec: TImageSpec;
  Src: TByteSource;
  LZ4R: TBrokkrResult<TLZ4FrameHeaderInfo>;
begin
  FillChar(Spec, SizeOf(Spec), 0);
  Spec.Kind := ikTarEntry;
  Spec.Path := TarPath;
  Spec.EntryName := E.Name;
  Spec.EntryDataOffset := E.DataOffset;
  Spec.EntryDiskSize := E.Size;
  Spec.SourceBaseName := ExtractFileName(StringReplace(E.Name, '/', '\', [rfReplaceAll]));
  Spec.IsLZ4 := IsLZ4Name(Spec.SourceBaseName);

  if Spec.IsLZ4 then
    Spec.BaseName := StripLZ4Suffix(Spec.SourceBaseName)
  else
    Spec.BaseName := Spec.SourceBaseName;

  Spec.DiskSize := E.Size;
  Spec.Display := TarPath + ' -> ' + E.Name;

  if Spec.IsLZ4 then
  begin
    Src := TTarEntrySource.Create(TarPath, E.Name, E.DataOffset, E.Size);
    try
      LZ4R := ParseLZ4FrameHeader(Src);
      if not LZ4R.IsOK then
        Exit(TBrokkrResult<TImageSpec>.Fail(LZ4R.Error));
      Spec.Size := LZ4R.Value.ContentSize;
    finally
      Src.Free;
    end;
  end
  else
    Spec.Size := Spec.DiskSize;

  Result := TBrokkrResult<TImageSpec>.OK(Spec);
end;

function ExpandInputsTarOrRaw(const Inputs: TStringList): TBrokkrResult<TList<TImageSpec>>;
var
  List: TList<TImageSpec>;
  I, J: Integer;
  FilePath: string;
  TarResult: TBrokkrResult<TTarArchive>;
  Tar: TTarArchive;
  E: TTarEntry;
  SpecResult: TBrokkrResult<TImageSpec>;
begin
  List := TList<TImageSpec>.Create;
  try
    for I := 0 to Inputs.Count - 1 do
    begin
      FilePath := Inputs[I];

      if TTarArchive.IsTarFile(FilePath) then
      begin
        TarResult := TTarArchive.Open(FilePath);
        if not TarResult.IsOK then
        begin
          List.Free;
          Exit(TBrokkrResult<TList<TImageSpec>>.Fail(TarResult.Error));
        end;

        Tar := TarResult.Value;
        try
          for J := 0 to Tar.Entries.Count - 1 do
          begin
            E := Tar.Entries[J];
            if E.Size = 0 then Continue;

            SpecResult := MakeSpecFromTarEntry(FilePath, E);
            if SpecResult.IsOK then
              List.Add(SpecResult.Value);
          end;
        finally
          Tar.Free;
        end;
      end
      else
      begin
        SpecResult := MakeSpecFromFile(FilePath);
        if not SpecResult.IsOK then
        begin
          List.Free;
          Exit(TBrokkrResult<TList<TImageSpec>>.Fail(SpecResult.Error));
        end;
        List.Add(SpecResult.Value);
      end;
    end;

    Result := TBrokkrResult<TList<TImageSpec>>.OK(List);
  except
    on Ex: Exception do
    begin
      List.Free;
      Result := TBrokkrResult<TList<TImageSpec>>.Fail(Ex.Message);
    end;
  end;
end;

function MapToPit(PitTable: TPitTable; Sources: TList<TImageSpec>): TBrokkrResult<TList<TFlashItem>>;
var
  Items: TList<TFlashItem>;
  I, Idx: Integer;
  Spec: TImageSpec;
  Item: TFlashItem;
begin
  Items := TList<TFlashItem>.Create;
  try
    for I := 0 to Sources.Count - 1 do
    begin
      Spec := Sources[I];
      Idx := PitTable.FindByFileName(Spec.BaseName);
      if Idx < 0 then
        Continue;

      Item.Part := PitTable.Partitions[Idx];
      Item.Spec := Spec;
      Items.Add(Item);
    end;

    if Items.Count = 0 then
    begin
      Items.Free;
      Exit(TBrokkrResult<TList<TFlashItem>>.Fail('No sources matched PIT entries'));
    end;

    Result := TBrokkrResult<TList<TFlashItem>>.OK(Items);
  except
    on Ex: Exception do
    begin
      Items.Free;
      Result := TBrokkrResult<TList<TFlashItem>>.Fail(Ex.Message);
    end;
  end;
end;

end.
