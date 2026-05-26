unit uGroupFlasher;

interface

uses
  SysUtils, Classes, Generics.Collections, SyncObjs, uStatus, uByteTransport,
  uOdinCmd, uOdinWire, uPit, uPitTransfer, uFlash, uByteSource;

type
  TTarget = class
  public
    ID: string;
    Link: IByteTransport;
    Init: TInitTargetInfo;
    Proto: TProtocolVersion;
    PitBytes: TBytes;
    PitTable: TPitTable;
    constructor Create;
    destructor Destroy; override;
  end;

  TPlanItemKind = (pikPit, pikPart);

  TPlanItem = record
    Kind: TPlanItemKind;
    PartID: Integer;
    DevType: Integer;
    PartName: string;
    PitFileName: string;
    SourceBase: string;
    Size: UInt64;
  end;

  TFlashCfg = record
    BufferBytes: NativeUInt;
    PktAllV2Plus: NativeUInt;
    PktAnyOld: NativeUInt;
    PreflashTimeoutMs: Integer;
    PreflashRetries: Cardinal;
    FlashTimeoutMs: Integer;
    RebootAfter: Boolean;

    class function Default: TFlashCfg; static;
  end;

  TOnDevicesProc = reference to procedure(Count: Integer; const Names: TStringList);
  TOnStageProc = reference to procedure(const Stage: string);
  TOnPlanProc = reference to procedure(const Plan: TList<TPlanItem>; TotalBytes: UInt64);
  TOnItemActiveProc = reference to procedure(Idx: Integer);
  TOnItemDoneProc = reference to procedure(Idx: Integer);
  TOnProgressProc = reference to procedure(Done, Total, ItemDone, ItemTotal: UInt64);
  TOnErrorProc = reference to procedure(const Msg: string);
  TOnDoneProc = reference to procedure;

  TFlashUI = record
    OnDevices: TOnDevicesProc;
    OnStage: TOnStageProc;
    OnPlan: TOnPlanProc;
    OnItemActive: TOnItemActiveProc;
    OnItemDone: TOnItemDoneProc;
    OnProgress: TOnProgressProc;
    OnError: TOnErrorProc;
    OnDone: TOnDoneProc;
  end;

function FlashDevices(Devices: TList<TTarget>; Sources: TList<TImageSpec>;
  const PitToUpload: TBytes; const Cfg: TFlashCfg; const UI: TFlashUI): TBrokkrStatus;

implementation

{ TTarget }

constructor TTarget.Create;
begin
  inherited;
  Proto := pvNone;
  PitTable := nil;
end;

destructor TTarget.Destroy;
begin
  PitTable.Free;
  inherited;
end;

{ TFlashCfg }

class function TFlashCfg.Default: TFlashCfg;
begin
  Result.BufferBytes := 30 * 1024 * 1024;
  Result.PktAllV2Plus := 1 * 1024 * 1024;
  Result.PktAnyOld := 128 * 1024;
  Result.PreflashTimeoutMs := 1000;
  Result.PreflashRetries := 2;
  Result.FlashTimeoutMs := 45000;
  Result.RebootAfter := True;
end;

function ChoosePacketSize(Devices: TList<TTarget>; const Cfg: TFlashCfg): NativeUInt;
var
  D: TTarget;
begin
  for D in Devices do
    if D.Proto < pvVer2 then
      Exit(Cfg.PktAnyOld);
  Result := Cfg.PktAllV2Plus;
end;

function FlashDevices(Devices: TList<TTarget>; Sources: TList<TImageSpec>;
  const PitToUpload: TBytes; const Cfg: TFlashCfg; const UI: TFlashUI): TBrokkrStatus;
var
  D: TTarget;
  Odin: TOdinCommands;
  St: TBrokkrStatus;
  VerResult: TBrokkrResult<TInitTargetInfo>;
  PitBytesResult: TBrokkrResult<TBytes>;
  PitTableResult: TBrokkrResult<TPitTable>;
  Items: TList<TFlashItem>;
  MapResult: TBrokkrResult<TList<TFlashItem>>;
  PktSize: NativeUInt;
  TotalSize: UInt64;
  I: Integer;
  Item: TFlashItem;
  Src: TByteSource;
  SrcResult: TBrokkrResult<TByteSource>;
  Buf: TBytes;
  BytesSent, ChunkSize: Integer;
  PlanItems: TList<TPlanItem>;
  Plan: TPlanItem;
  ShutMode: TShutdownMode;
begin
  if Devices.Count = 0 then
    Exit(TBrokkrStatus.Fail('No devices'));

  for D in Devices do
    if (D.Link = nil) or (not D.Link.Connected) then
      Exit(TBrokkrStatus.Fail('Transport not connected'));

  if Assigned(UI.OnStage) then UI.OnStage('ODIN handshake');

  for D in Devices do
  begin
    Odin := TOdinCommands.Create(D.Link);
    try
      D.Link.SetTimeoutMs(Cfg.PreflashTimeoutMs);

      St := Odin.Handshake(Cfg.PreflashRetries);
      if not St.IsOK then
      begin
        if Assigned(UI.OnError) then UI.OnError('Handshake failed: ' + St.Error);
        Exit(St);
      end;

      VerResult := Odin.GetVersion(Cfg.PreflashRetries);
      if not VerResult.IsOK then
      begin
        if Assigned(UI.OnError) then UI.OnError('GetVersion failed: ' + VerResult.Error);
        Exit(TBrokkrStatus.Fail(VerResult.Error));
      end;

      D.Init := VerResult.Value;
      D.Proto := D.Init.Protocol;
    finally
      Odin.Free;
    end;
  end;

  if Assigned(UI.OnStage) then UI.OnStage('Negotiating transfer options');

  PktSize := ChoosePacketSize(Devices, Cfg);

  for D in Devices do
  begin
    Odin := TOdinCommands.Create(D.Link);
    try
      St := Odin.SetupTransferOptions(Integer(PktSize), Cfg.PreflashRetries);
      if not St.IsOK then
      begin
        if Assigned(UI.OnError) then UI.OnError('SetupTransferOptions failed: ' + St.Error);
        Exit(St);
      end;
    finally
      Odin.Free;
    end;
  end;

  if Assigned(UI.OnStage) then UI.OnStage('Downloading PIT(s)');

  for D in Devices do
  begin
    Odin := TOdinCommands.Create(D.Link);
    try
      PitBytesResult := DownloadPitBytes(Odin, Cfg.PreflashRetries);
      if not PitBytesResult.IsOK then
      begin
        if Assigned(UI.OnError) then UI.OnError('PIT download failed: ' + PitBytesResult.Error);
        Exit(TBrokkrStatus.Fail(PitBytesResult.Error));
      end;
      D.PitBytes := PitBytesResult.Value;

      PitTableResult := ParsePit(D.PitBytes);
      if not PitTableResult.IsOK then
      begin
        if Assigned(UI.OnError) then UI.OnError('PIT parse failed: ' + PitTableResult.Error);
        Exit(TBrokkrStatus.Fail(PitTableResult.Error));
      end;
      D.PitTable := PitTableResult.Value;
    finally
      Odin.Free;
    end;
  end;

  if Length(PitToUpload) > 0 then
  begin
    if Assigned(UI.OnStage) then UI.OnStage('Uploading PIT');
    for D in Devices do
    begin
      Odin := TOdinCommands.Create(D.Link);
      try
        St := Odin.SetPit(PitToUpload, Cfg.PreflashRetries);
        if not St.IsOK then
        begin
          if Assigned(UI.OnError) then UI.OnError('PIT upload failed: ' + St.Error);
          Exit(St);
        end;
      finally
        Odin.Free;
      end;
    end;
  end;

  if Sources.Count = 0 then
  begin
    if Assigned(UI.OnDone) then UI.OnDone();
    Exit(TBrokkrStatus.OK);
  end;

  D := Devices[0];
  MapResult := MapToPit(D.PitTable, Sources);
  if not MapResult.IsOK then
  begin
    if Assigned(UI.OnError) then UI.OnError('PIT mapping failed: ' + MapResult.Error);
    Exit(TBrokkrStatus.Fail(MapResult.Error));
  end;
  Items := MapResult.Value;

  TotalSize := 0;
  PlanItems := TList<TPlanItem>.Create;
  try
    for I := 0 to Items.Count - 1 do
    begin
      Item := Items[I];
      TotalSize := TotalSize + Item.Spec.Size;
      Plan.Kind := pikPart;
      Plan.PartID := Item.Part.ID;
      Plan.DevType := Item.Part.DevType;
      Plan.PartName := Item.Part.Name;
      Plan.PitFileName := Item.Part.FileName;
      Plan.SourceBase := Item.Spec.BaseName;
      Plan.Size := Item.Spec.Size;
      PlanItems.Add(Plan);
    end;

    if Assigned(UI.OnPlan) then UI.OnPlan(PlanItems, TotalSize);
  finally
    PlanItems.Free;
  end;

  if Assigned(UI.OnStage) then UI.OnStage('Sending total size');

  for D in Devices do
  begin
    Odin := TOdinCommands.Create(D.Link);
    try
      St := Odin.SendTotalSize(TotalSize, D.Proto, Cfg.PreflashRetries);
      if not St.IsOK then
      begin
        if Assigned(UI.OnError) then UI.OnError('SendTotalSize failed: ' + St.Error);
        Exit(St);
      end;
    finally
      Odin.Free;
    end;
  end;

  if Assigned(UI.OnStage) then UI.OnStage('Flashing');

  D := Devices[0];
  D.Link.SetTimeoutMs(Cfg.FlashTimeoutMs);

  Odin := TOdinCommands.Create(D.Link);
  try
    for I := 0 to Items.Count - 1 do
    begin
      Item := Items[I];
      if Assigned(UI.OnItemActive) then UI.OnItemActive(I);

      SrcResult := Item.Spec.Open;
      if not SrcResult.IsOK then
      begin
        if Assigned(UI.OnError) then UI.OnError('Open failed: ' + SrcResult.Error);
        Exit(TBrokkrStatus.Fail(SrcResult.Error));
      end;

      Src := SrcResult.Value;
      try
        SetLength(Buf, Integer(PktSize));
        BytesSent := 0;

        St := Odin.BeginDownload(Integer(Item.Spec.Size), Cfg.PreflashRetries);
        if not St.IsOK then
        begin
          if Assigned(UI.OnError) then UI.OnError('BeginDownload failed: ' + St.Error);
          Exit(St);
        end;

        while UInt64(BytesSent) < Item.Spec.Size do
        begin
          ChunkSize := Src.Read(Buf, 0, Length(Buf));
          if ChunkSize <= 0 then Break;

          if ChunkSize < Length(Buf) then
            FillChar(Buf[ChunkSize], Length(Buf) - ChunkSize, 0);

          St := Odin.SendRaw(Copy(Buf, 0, Length(Buf)), 8);
          if not St.IsOK then
          begin
            if Assigned(UI.OnError) then UI.OnError('SendRaw failed: ' + St.Error);
            Exit(St);
          end;

          Odin.Conn.RecvZLP;
          Inc(BytesSent, ChunkSize);

          if Assigned(UI.OnProgress) then
            UI.OnProgress(UInt64(BytesSent), TotalSize, UInt64(BytesSent), Item.Spec.Size);
        end;

        St := Odin.EndDownload(
          Integer(Item.Spec.Size),
          Item.Part.ID,
          Item.Part.DevType,
          I = Items.Count - 1
        );
        if not St.IsOK then
        begin
          if Assigned(UI.OnError) then UI.OnError('EndDownload failed: ' + St.Error);
          Exit(St);
        end;
      finally
        Src.Free;
      end;

      if Assigned(UI.OnItemDone) then UI.OnItemDone(I);
    end;
  finally
    Odin.Free;
  end;

  if Cfg.RebootAfter then
    ShutMode := smReboot
  else
    ShutMode := smNoReboot;

  if Assigned(UI.OnStage) then
  begin
    if ShutMode = smReboot then
      UI.OnStage('Finalizing + reboot')
    else
      UI.OnStage('Finalizing');
  end;

  for D in Devices do
  begin
    Odin := TOdinCommands.Create(D.Link);
    try
      St := Odin.Shutdown(ShutMode);
      if not St.IsOK then
        if Assigned(UI.OnError) then UI.OnError('Shutdown failed: ' + St.Error);
    finally
      Odin.Free;
    end;
  end;

  Items.Free;

  if Assigned(UI.OnDone) then UI.OnDone();
  Result := TBrokkrStatus.OK;
end;

end.
