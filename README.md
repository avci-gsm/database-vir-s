# Brokkr Flash - Delphi Port

Samsung cihazlari icin modern bir flash (yazilim yukleme) araci.
[brokkr-flash](https://github.com/Gabriel2392/brokkr-flash) C++ projesinin Delphi (Object Pascal) portudur.

## Ozellikler

- Samsung telefonlara firmware/ROM yukleme (Odin protokolu)
- GUI (VCL) ve CLI arayuzu
- TAR arsiv destegi (Samsung firmware dosyalari)
- LZ4 sikistirma destegi
- PIT (Partition Information Table) okuma/yazma
- Kablosuz flash destegi (TCP port 13579)
- Coklu cihaz algilama

## Gereksinimler

- **Delphi 10.3+** (veya Delphi 11/12)
- **Windows 10+**
- Samsung USB surculeri (veya WinUSB)

## Derleme

1. `BrokkrFlash.dpr` dosyasini Delphi IDE'de acin
2. Platform olarak **Win32** veya **Win64** secin
3. Build > Build (Ctrl+F9)

## Proje Yapisi

```
BrokkrFlash.dpr          - Ana proje dosyasi
gui/
  uMainForm.pas/.dfm     - Ana form (GUI)
src/
  uCliMode.pas           - CLI modu
  core/
    uStatus.pas          - Hata yonetimi (Status/Result)
    uEndian.pas          - Little-endian donusumleri
    uByteTransport.pas   - Soyut transport arayuzu
    uThreadPool.pas      - Thread havuzu
  io/
    uByteSource.pas      - Dosya okuma katmani
    uTar.pas             - TAR arsiv parser
    uLZ4Frame.pas        - LZ4 frame header parser
  protocol/odin/
    uOdinWire.pas        - Odin protokol wire tipleri
    uOdinCmd.pas         - Odin komutlari (handshake, transfer, vb.)
    uPit.pas             - PIT tablo parser
    uPitTransfer.pas     - PIT indirme/yukleme
    uFlash.pas           - Flash islem mantigi
    uGroupFlasher.pas    - Coklu cihaz flash yoneticisi
  platform/windows/
    uWinUSBDevice.pas    - WinUSB cihaz erisimi
    uWinUSBConn.pas      - WinUSB baglanti yonetimi
    uSysfsUSB.pas        - USB cihaz listeleme
    uTcpTransport.pas    - TCP baglanti (kablosuz flash)
```

## CLI Kullanimi

```
BrokkrFlash.exe -b BL.tar -a AP.tar -c CP.tar -s CSC.tar
BrokkrFlash.exe --list
BrokkrFlash.exe --wireless -a AP.tar
BrokkrFlash.exe --help
```

## Lisans

GPL-3.0 (Orijinal brokkr-flash projesi ile ayni)

## Krediler

- Orijinal C++ projesi: [Gabriel2392/brokkr-flash](https://github.com/Gabriel2392/brokkr-flash)
- Odin protokolu tersine muhendislik: Samsung toplulugu
