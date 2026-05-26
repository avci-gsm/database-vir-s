object frmMain: TfrmMain
  Left = 0
  Top = 0
  Caption = 'Brokkr Flash - Samsung Device Flasher'
  ClientHeight = 620
  ClientWidth = 780
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poScreenCenter
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  OnClose = FormClose
  PixelsPerInch = 96
  TextHeight = 13
  object pnlTop: TPanel
    Left = 0
    Top = 0
    Width = 780
    Height = 50
    Align = alTop
    BevelOuter = bvNone
    Color = clNavy
    ParentBackground = False
    TabOrder = 0
    object lblTitle: TLabel
      Left = 16
      Top = 8
      Width = 200
      Height = 30
      Caption = 'Brokkr Flash'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWhite
      Font.Height = -20
      Font.Name = 'Segoe UI'
      Font.Style = [fsBold]
      ParentFont = False
    end
    object lblVersion: TLabel
      Left = 680
      Top = 16
      Width = 90
      Height = 15
      Alignment = taRightJustify
      Caption = 'v1.4.5 (Delphi)'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clSilver
      Font.Height = -11
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
    end
  end
  object pnlFiles: TPanel
    Left = 0
    Top = 50
    Width = 560
    Height = 320
    Align = alLeft
    BevelOuter = bvNone
    TabOrder = 1
    object grpFiles: TGroupBox
      Left = 8
      Top = 8
      Width = 544
      Height = 304
      Caption = ' Flash Dosyalari '
      TabOrder = 0
      object lblBL: TLabel
        Left = 16
        Top = 28
        Width = 14
        Height = 15
        Caption = 'BL'
      end
      object edtBL: TEdit
        Left = 56
        Top = 25
        Width = 400
        Height = 23
        TabOrder = 0
      end
      object btnBrowseBL: TButton
        Left = 464
        Top = 24
        Width = 65
        Height = 25
        Caption = 'Gozat...'
        TabOrder = 1
        OnClick = btnBrowseBLClick
      end
      object lblAP: TLabel
        Left = 16
        Top = 58
        Width = 14
        Height = 15
        Caption = 'AP'
      end
      object edtAP: TEdit
        Left = 56
        Top = 55
        Width = 400
        Height = 23
        TabOrder = 2
      end
      object btnBrowseAP: TButton
        Left = 464
        Top = 54
        Width = 65
        Height = 25
        Caption = 'Gozat...'
        TabOrder = 3
        OnClick = btnBrowseAPClick
      end
      object lblCP: TLabel
        Left = 16
        Top = 88
        Width = 14
        Height = 15
        Caption = 'CP'
      end
      object edtCP: TEdit
        Left = 56
        Top = 85
        Width = 400
        Height = 23
        TabOrder = 4
      end
      object btnBrowseCP: TButton
        Left = 464
        Top = 84
        Width = 65
        Height = 25
        Caption = 'Gozat...'
        TabOrder = 5
        OnClick = btnBrowseCPClick
      end
      object lblCSC: TLabel
        Left = 16
        Top = 118
        Width = 21
        Height = 15
        Caption = 'CSC'
      end
      object edtCSC: TEdit
        Left = 56
        Top = 115
        Width = 400
        Height = 23
        TabOrder = 6
      end
      object btnBrowseCSC: TButton
        Left = 464
        Top = 114
        Width = 65
        Height = 25
        Caption = 'Gozat...'
        TabOrder = 7
        OnClick = btnBrowseCSCClick
      end
      object lblUserData: TLabel
        Left = 16
        Top = 148
        Width = 30
        Height = 15
        Caption = 'DATA'
      end
      object edtUserData: TEdit
        Left = 56
        Top = 145
        Width = 400
        Height = 23
        TabOrder = 8
      end
      object btnBrowseUserData: TButton
        Left = 464
        Top = 144
        Width = 65
        Height = 25
        Caption = 'Gozat...'
        TabOrder = 9
        OnClick = btnBrowseUserDataClick
      end
      object lblPIT: TLabel
        Left = 16
        Top = 188
        Width = 16
        Height = 15
        Caption = 'PIT'
      end
      object edtPIT: TEdit
        Left = 56
        Top = 185
        Width = 400
        Height = 23
        TabOrder = 10
      end
      object btnBrowsePIT: TButton
        Left = 464
        Top = 184
        Width = 65
        Height = 25
        Caption = 'Gozat...'
        TabOrder = 11
        OnClick = btnBrowsePITClick
      end
      object chkUsePit: TCheckBox
        Left = 56
        Top = 215
        Width = 180
        Height = 17
        Caption = 'PIT dosyasi kullan'
        TabOrder = 12
      end
      object chkNoReboot: TCheckBox
        Left = 56
        Top = 238
        Width = 180
        Height = 17
        Caption = 'Yeniden baslatma'
        TabOrder = 13
      end
      object chkWireless: TCheckBox
        Left = 56
        Top = 261
        Width = 180
        Height = 17
        Caption = 'Kablosuz (Wi-Fi) flash'
        TabOrder = 14
      end
    end
  end
  object pnlDevices: TPanel
    Left = 560
    Top = 50
    Width = 220
    Height = 320
    Align = alClient
    BevelOuter = bvNone
    TabOrder = 2
    object lblDevices: TLabel
      Left = 8
      Top = 8
      Width = 54
      Height = 15
      Caption = 'Cihazlar:'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -11
      Font.Name = 'Segoe UI'
      Font.Style = [fsBold]
      ParentFont = False
    end
    object lbDevices: TListBox
      Left = 8
      Top = 28
      Width = 204
      Height = 250
      ItemHeight = 13
      TabOrder = 0
    end
    object btnRefreshDevices: TButton
      Left = 8
      Top = 284
      Width = 204
      Height = 25
      Caption = 'Cihazlari Yenile'
      TabOrder = 1
      OnClick = btnRefreshDevicesClick
    end
  end
  object pnlBottom: TPanel
    Left = 0
    Top = 370
    Width = 780
    Height = 50
    Align = alBottom
    BevelOuter = bvNone
    TabOrder = 3
    object btnStart: TButton
      Left = 16
      Top = 8
      Width = 120
      Height = 33
      Caption = 'BASLAT'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clGreen
      Font.Height = -13
      Font.Name = 'Segoe UI'
      Font.Style = [fsBold]
      ParentFont = False
      TabOrder = 0
      OnClick = btnStartClick
    end
    object btnReset: TButton
      Left = 152
      Top = 8
      Width = 100
      Height = 33
      Caption = 'TEMIZLE'
      TabOrder = 1
      OnClick = btnResetClick
    end
    object pbProgress: TProgressBar
      Left = 270
      Top = 14
      Width = 380
      Height = 22
      TabOrder = 2
    end
    object lblStatus: TLabel
      Left = 660
      Top = 17
      Width = 110
      Height = 15
      Alignment = taRightJustify
      Caption = 'Hazir'
    end
  end
  object pnlLog: TPanel
    Left = 0
    Top = 420
    Width = 780
    Height = 200
    Align = alBottom
    BevelOuter = bvNone
    TabOrder = 4
    object memoLog: TMemo
      Left = 8
      Top = 4
      Width = 764
      Height = 190
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -11
      Font.Name = 'Consolas'
      Font.Style = []
      ParentFont = False
      ReadOnly = True
      ScrollBars = ssVertical
      TabOrder = 0
    end
  end
  object tmrDeviceRefresh: TTimer
    Interval = 3000
    OnTimer = tmrDeviceRefreshTimer
    Left = 720
    Top = 8
  end
  object dlgOpen: TOpenDialog
    Left = 680
    Top = 8
  end
end
