program BrokkrFlash;

{$APPTYPE GUI}

uses
  Vcl.Forms,
  SysUtils,
  uMainForm in 'gui\uMainForm.pas' {frmMain},
  uCliMode in 'src\uCliMode.pas',
  uStatus in 'src\core\uStatus.pas',
  uEndian in 'src\core\uEndian.pas',
  uByteTransport in 'src\core\uByteTransport.pas',
  uThreadPool in 'src\core\uThreadPool.pas',
  uByteSource in 'src\io\uByteSource.pas',
  uTar in 'src\io\uTar.pas',
  uLZ4Frame in 'src\io\uLZ4Frame.pas',
  uOdinWire in 'src\protocol\odin\uOdinWire.pas',
  uOdinCmd in 'src\protocol\odin\uOdinCmd.pas',
  uPit in 'src\protocol\odin\uPit.pas',
  uPitTransfer in 'src\protocol\odin\uPitTransfer.pas',
  uFlash in 'src\protocol\odin\uFlash.pas',
  uGroupFlasher in 'src\protocol\odin\uGroupFlasher.pas',
  uWinUSBDevice in 'src\platform\windows\uWinUSBDevice.pas',
  uWinUSBConn in 'src\platform\windows\uWinUSBConn.pas',
  uSysfsUSB in 'src\platform\windows\uSysfsUSB.pas',
  uTcpTransport in 'src\platform\windows\uTcpTransport.pas';

{$R *.res}

begin
  if CliMode.ShouldRunCli then
  begin
    ExitCode := CliMode.RunCli;
    Exit;
  end;

  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.Title := 'Brokkr Flash';
  Application.CreateForm(TfrmMain, frmMain);
  Application.Run;
end.
