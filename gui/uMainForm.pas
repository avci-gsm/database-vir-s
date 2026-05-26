unit uMainForm;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes,
  System.Generics.Collections, Vcl.Graphics, Vcl.Controls, Vcl.Forms,
  Vcl.Dialogs, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.ComCtrls, Vcl.Grids,
  uStatus, uByteTransport, uOdinCmd, uOdinWire, uPit, uFlash, uGroupFlasher,
  uSysfsUSB, uWinUSBDevice, uWinUSBConn, uTcpTransport;

type
  TfrmMain = class(TForm)
    pnlTop: TPanel;
    pnlFiles: TPanel;
    pnlBottom: TPanel;
    pnlLog: TPanel;

    lblTitle: TLabel;
    lblVersion: TLabel;

    grpFiles: TGroupBox;
    lblBL: TLabel;
    lblAP: TLabel;
    lblCP: TLabel;
    lblCSC: TLabel;
    lblUserData: TLabel;
    lblPIT: TLabel;

    edtBL: TEdit;
    edtAP: TEdit;
    edtCP: TEdit;
    edtCSC: TEdit;
    edtUserData: TEdit;
    edtPIT: TEdit;

    btnBrowseBL: TButton;
    btnBrowseAP: TButton;
    btnBrowseCP: TButton;
    btnBrowseCSC: TButton;
    btnBrowseUserData: TButton;
    btnBrowsePIT: TButton;

    chkUsePit: TCheckBox;
    chkNoReboot: TCheckBox;
    chkWireless: TCheckBox;

    btnStart: TButton;
    btnReset: TButton;

    memoLog: TMemo;
    pbProgress: TProgressBar;
    lblStatus: TLabel;

    pnlDevices: TPanel;
    lblDevices: TLabel;
    lbDevices: TListBox;
    btnRefreshDevices: TButton;

    tmrDeviceRefresh: TTimer;
    dlgOpen: TOpenDialog;

    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);

    procedure btnBrowseBLClick(Sender: TObject);
    procedure btnBrowseAPClick(Sender: TObject);
    procedure btnBrowseCPClick(Sender: TObject);
    procedure btnBrowseCSCClick(Sender: TObject);
    procedure btnBrowseUserDataClick(Sender: TObject);
    procedure btnBrowsePITClick(Sender: TObject);

    procedure btnStartClick(Sender: TObject);
    procedure btnResetClick(Sender: TObject);
    procedure btnRefreshDevicesClick(Sender: TObject);
    procedure tmrDeviceRefreshTimer(Sender: TObject);
  private
    FBusy: Boolean;
    FFlashThread: TThread;

    procedure Log(const Msg: string);
    procedure LogError(const Msg: string);
    procedure SetBusy(ABusy: Boolean);
    procedure BrowseFile(Edit: TEdit; const Filter: string);
    procedure RefreshDevices;
    procedure DoFlash;
    procedure OnFlashDone(Success: Boolean; const ErrMsg: string);
  public
  end;

var
  frmMain: TfrmMain;

implementation

{$R *.dfm}

uses
  System.IOUtils;

type
  TFlashThread = class(TThread)
  private
    FForm: TfrmMain;
    FSuccess: Boolean;
    FErrMsg: string;
  protected
    procedure Execute; override;
  public
    constructor Create(AForm: TfrmMain);
  end;

{ TFlashThread }

constructor TFlashThread.Create(AForm: TfrmMain);
begin
  FForm := AForm;
  FSuccess := False;
  FErrMsg := '';
  FreeOnTerminate := True;
  inherited Create(False);
end;

procedure TFlashThread.Execute;
begin
  try
    FForm.DoFlash;
    FSuccess := True;
  except
    on E: Exception do
    begin
      FSuccess := False;
      FErrMsg := E.Message;
    end;
  end;

  Synchronize(procedure
  begin
    FForm.OnFlashDone(FSuccess, FErrMsg);
  end);
end;

{ TfrmMain }

procedure TfrmMain.FormCreate(Sender: TObject);
begin
  Caption := 'Brokkr Flash - Samsung Device Flasher (Delphi)';
  Width := 800;
  Height := 650;
  Position := poScreenCenter;

  FBusy := False;

  lblTitle.Caption := 'Brokkr Flash';
  lblTitle.Font.Size := 16;
  lblTitle.Font.Style := [fsBold];
  lblTitle.Font.Color := clNavy;
  lblVersion.Caption := 'v1.4.5 (Delphi Port)';

  pbProgress.Min := 0;
  pbProgress.Max := 100;
  pbProgress.Position := 0;

  lblStatus.Caption := 'Hazir';
  memoLog.Clear;
  Log('Brokkr Flash baslatildi.');
  Log('Samsung cihazinizi download moduna alin (Volume Down + Power)');

  tmrDeviceRefresh.Interval := 3000;
  tmrDeviceRefresh.Enabled := True;
  RefreshDevices;
end;

procedure TfrmMain.FormDestroy(Sender: TObject);
begin
  tmrDeviceRefresh.Enabled := False;
end;

procedure TfrmMain.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  if FBusy then
  begin
    if MessageDlg('Flash islemi devam ediyor. Cikmak istediginize emin misiniz?',
      mtWarning, [mbYes, mbNo], 0) <> mrYes then
    begin
      Action := caNone;
      Exit;
    end;
  end;
  Action := caFree;
end;

procedure TfrmMain.Log(const Msg: string);
begin
  if GetCurrentThreadId <> MainThreadID then
  begin
    TThread.Synchronize(nil, procedure
    begin
      memoLog.Lines.Add(FormatDateTime('hh:nn:ss', Now) + ' ' + Msg);
    end);
  end
  else
    memoLog.Lines.Add(FormatDateTime('hh:nn:ss', Now) + ' ' + Msg);
end;

procedure TfrmMain.LogError(const Msg: string);
begin
  Log('[HATA] ' + Msg);
end;

procedure TfrmMain.SetBusy(ABusy: Boolean);
begin
  FBusy := ABusy;
  btnStart.Enabled := not ABusy;
  btnReset.Enabled := not ABusy;
  edtBL.Enabled := not ABusy;
  edtAP.Enabled := not ABusy;
  edtCP.Enabled := not ABusy;
  edtCSC.Enabled := not ABusy;
  edtUserData.Enabled := not ABusy;
  edtPIT.Enabled := not ABusy;
  btnBrowseBL.Enabled := not ABusy;
  btnBrowseAP.Enabled := not ABusy;
  btnBrowseCP.Enabled := not ABusy;
  btnBrowseCSC.Enabled := not ABusy;
  btnBrowseUserData.Enabled := not ABusy;
  btnBrowsePIT.Enabled := not ABusy;

  if ABusy then
    lblStatus.Caption := 'Flash islemi devam ediyor...'
  else
    lblStatus.Caption := 'Hazir';
end;

procedure TfrmMain.BrowseFile(Edit: TEdit; const Filter: string);
begin
  dlgOpen.Filter := Filter;
  if dlgOpen.Execute then
    Edit.Text := dlgOpen.FileName;
end;

procedure TfrmMain.btnBrowseBLClick(Sender: TObject);
begin
  BrowseFile(edtBL, 'TAR dosyalari (*.tar;*.tar.md5)|*.tar;*.tar.md5|Tum dosyalar|*.*');
end;

procedure TfrmMain.btnBrowseAPClick(Sender: TObject);
begin
  BrowseFile(edtAP, 'TAR dosyalari (*.tar;*.tar.md5)|*.tar;*.tar.md5|Tum dosyalar|*.*');
end;

procedure TfrmMain.btnBrowseCPClick(Sender: TObject);
begin
  BrowseFile(edtCP, 'TAR dosyalari (*.tar;*.tar.md5)|*.tar;*.tar.md5|Tum dosyalar|*.*');
end;

procedure TfrmMain.btnBrowseCSCClick(Sender: TObject);
begin
  BrowseFile(edtCSC, 'TAR dosyalari (*.tar;*.tar.md5)|*.tar;*.tar.md5|Tum dosyalar|*.*');
end;

procedure TfrmMain.btnBrowseUserDataClick(Sender: TObject);
begin
  BrowseFile(edtUserData, 'TAR dosyalari (*.tar;*.tar.md5)|*.tar;*.tar.md5|Tum dosyalar|*.*');
end;

procedure TfrmMain.btnBrowsePITClick(Sender: TObject);
begin
  BrowseFile(edtPIT, 'PIT dosyalari (*.pit)|*.pit|Tum dosyalar|*.*');
end;

procedure TfrmMain.btnStartClick(Sender: TObject);
var
  HasFile: Boolean;
begin
  HasFile := (edtBL.Text <> '') or (edtAP.Text <> '') or (edtCP.Text <> '') or
             (edtCSC.Text <> '') or (edtUserData.Text <> '') or
             (chkUsePit.Checked and (edtPIT.Text <> ''));

  if not HasFile then
  begin
    MessageDlg('En az bir dosya secmelisiniz!', mtWarning, [mbOK], 0);
    Exit;
  end;

  if lbDevices.Count = 0 then
  begin
    if not chkWireless.Checked then
    begin
      MessageDlg('Bagli Samsung cihazi bulunamadi!', mtWarning, [mbOK], 0);
      Exit;
    end;
  end;

  if MessageDlg('Flash islemini baslatmak istediginize emin misiniz?' + sLineBreak +
    'Bu islem cihazinizdaki verileri silebilir!',
    mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
    Exit;

  SetBusy(True);
  pbProgress.Position := 0;
  memoLog.Lines.Add('');
  Log('Flash islemi baslatiliyor...');

  FFlashThread := TFlashThread.Create(Self);
end;

procedure TfrmMain.btnResetClick(Sender: TObject);
begin
  edtBL.Text := '';
  edtAP.Text := '';
  edtCP.Text := '';
  edtCSC.Text := '';
  edtUserData.Text := '';
  edtPIT.Text := '';
  chkUsePit.Checked := False;
  chkNoReboot.Checked := False;
  pbProgress.Position := 0;
  lblStatus.Caption := 'Hazir';
  Log('Alanlar temizlendi.');
end;

procedure TfrmMain.btnRefreshDevicesClick(Sender: TObject);
begin
  RefreshDevices;
end;

procedure TfrmMain.tmrDeviceRefreshTimer(Sender: TObject);
begin
  if not FBusy then
    RefreshDevices;
end;

procedure TfrmMain.RefreshDevices;
var
  Filter: TEnumerateFilter;
  DevList: TList<TUsbDeviceSysfsInfo>;
  I: Integer;
begin
  lbDevices.Items.Clear;

  Filter.Vendor := SAMSUNG_VID;
  Filter.Products := TArray<Word>.Create($6601, $685D, $68C3);
  DevList := EnumerateUSBDevices(Filter);
  try
    if DevList.Count = 0 then
      lbDevices.Items.Add('(Cihaz bulunamadi)')
    else
    begin
      for I := 0 to DevList.Count - 1 do
        lbDevices.Items.Add(DevList[I].Describe);
    end;
  finally
    DevList.Free;
  end;
end;

procedure TfrmMain.DoFlash;
var
  Inputs: TStringList;
  Sources: TList<TImageSpec>;
  ExpandResult: TBrokkrResult<TList<TImageSpec>>;
  Cfg: TFlashCfg;
  UI: TFlashUI;
  Devices: TList<TTarget>;
  Dev: TTarget;
  Conn: TWinUSBConnection;
  USBDev: TWinUSBDevice;
  TcpConn: TTcpConnection;
  DevList: TList<TUsbDeviceSysfsInfo>;
  Filter: TEnumerateFilter;
  PitData: TBytes;
  FS: TFileStream;
  St: TBrokkrStatus;
begin
  Inputs := TStringList.Create;
  try
    if edtBL.Text <> '' then Inputs.Add(edtBL.Text);
    if edtAP.Text <> '' then Inputs.Add(edtAP.Text);
    if edtCP.Text <> '' then Inputs.Add(edtCP.Text);
    if edtCSC.Text <> '' then Inputs.Add(edtCSC.Text);
    if edtUserData.Text <> '' then Inputs.Add(edtUserData.Text);

    ExpandResult := ExpandInputsTarOrRaw(Inputs);
    if not ExpandResult.IsOK then
      raise EBrokkrError.Create(ExpandResult.Error);
    Sources := ExpandResult.Value;
  finally
    Inputs.Free;
  end;

  SetLength(PitData, 0);
  if chkUsePit.Checked and (edtPIT.Text <> '') then
  begin
    FS := TFileStream.Create(edtPIT.Text, fmOpenRead);
    try
      SetLength(PitData, FS.Size);
      FS.ReadBuffer(PitData[0], FS.Size);
    finally
      FS.Free;
    end;
  end;

  Devices := TList<TTarget>.Create;
  try
    if chkWireless.Checked then
    begin
      Log('Kablosuz baglanti bekleniyor (port ' + IntToStr(WIRELESS_PORT) + ')...');
      TcpConn := TTcpConnection.Create;
      St := TcpConn.Accept;
      if not St.IsOK then
        raise EBrokkrError.Create('Kablosuz baglanti hatasi: ' + St.Error);

      Dev := TTarget.Create;
      Dev.ID := 'wireless';
      Dev.Link := TcpConn;
      Devices.Add(Dev);
    end
    else
    begin
      Filter.Vendor := SAMSUNG_VID;
      Filter.Products := TArray<Word>.Create($6601, $685D, $68C3);
      DevList := EnumerateUSBDevices(Filter);
      try
        if DevList.Count = 0 then
          raise EBrokkrError.Create('Bagli Samsung cihazi bulunamadi!');

        USBDev := TWinUSBDevice.Create(DevList[0].DevNodePath);
        Conn := TWinUSBConnection.Create(USBDev);
        St := Conn.Open;
        if not St.IsOK then
          raise EBrokkrError.Create('USB baglanti hatasi: ' + St.Error);

        Dev := TTarget.Create;
        Dev.ID := DevList[0].SysName;
        Dev.Link := Conn;
        Devices.Add(Dev);
      finally
        DevList.Free;
      end;
    end;

    Cfg := TFlashCfg.Default;
    Cfg.RebootAfter := not chkNoReboot.Checked;

    UI.OnStage := procedure(const Stage: string)
    begin
      Log('[ASAMA] ' + Stage);
    end;

    UI.OnProgress := procedure(Done, Total, ItemDone, ItemTotal: UInt64)
    begin
      TThread.Synchronize(nil, procedure
      begin
        if Total > 0 then
          pbProgress.Position := Integer((Done * 100) div Total);
      end);
    end;

    UI.OnError := procedure(const Msg: string)
    begin
      LogError(Msg);
    end;

    UI.OnDone := procedure
    begin
      Log('Flash islemi tamamlandi!');
    end;

    UI.OnItemActive := procedure(Idx: Integer)
    begin
      Log(Format('[PARCA %d] Flash ediliyor...', [Idx]));
    end;

    UI.OnItemDone := procedure(Idx: Integer)
    begin
      Log(Format('[PARCA %d] Tamamlandi', [Idx]));
    end;

    St := FlashDevices(Devices, Sources, PitData, Cfg, UI);
    if not St.IsOK then
      raise EBrokkrError.Create(St.Error);
  finally
    Devices.Free;
    Sources.Free;
  end;
end;

procedure TfrmMain.OnFlashDone(Success: Boolean; const ErrMsg: string);
begin
  SetBusy(False);
  if Success then
  begin
    pbProgress.Position := 100;
    lblStatus.Caption := 'Flash basarili!';
    Log('Islem basariyla tamamlandi.');
    MessageDlg('Flash islemi basariyla tamamlandi!', mtInformation, [mbOK], 0);
  end
  else
  begin
    lblStatus.Caption := 'Flash basarisiz!';
    LogError(ErrMsg);
    MessageDlg('Flash islemi basarisiz: ' + ErrMsg, mtError, [mbOK], 0);
  end;
end;

end.
