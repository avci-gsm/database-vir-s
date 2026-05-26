unit uEndian;

interface

function LEToHost16(V: Word): Word; inline;
function LEToHost32(V: Integer): Integer; inline;
function LEToHost32U(V: Cardinal): Cardinal; inline;
function HostToLE32(V: Integer): Integer; inline;
function HostToLE32U(V: Cardinal): Cardinal; inline;
function SwapBytes16(V: Word): Word; inline;
function SwapBytes32(V: Cardinal): Cardinal; inline;

implementation

function SwapBytes16(V: Word): Word;
begin
  Result := (V shr 8) or (V shl 8);
end;

function SwapBytes32(V: Cardinal): Cardinal;
begin
  Result := ((V and $FF) shl 24) or
            ((V and $FF00) shl 8) or
            ((V and $FF0000) shr 8) or
            ((V and $FF000000) shr 24);
end;

function LEToHost16(V: Word): Word;
begin
  {$IFDEF ENDIAN_BIG}
  Result := SwapBytes16(V);
  {$ELSE}
  Result := V;
  {$ENDIF}
end;

function LEToHost32(V: Integer): Integer;
begin
  {$IFDEF ENDIAN_BIG}
  Result := Integer(SwapBytes32(Cardinal(V)));
  {$ELSE}
  Result := V;
  {$ENDIF}
end;

function LEToHost32U(V: Cardinal): Cardinal;
begin
  {$IFDEF ENDIAN_BIG}
  Result := SwapBytes32(V);
  {$ELSE}
  Result := V;
  {$ENDIF}
end;

function HostToLE32(V: Integer): Integer;
begin
  {$IFDEF ENDIAN_BIG}
  Result := Integer(SwapBytes32(Cardinal(V)));
  {$ELSE}
  Result := V;
  {$ENDIF}
end;

function HostToLE32U(V: Cardinal): Cardinal;
begin
  {$IFDEF ENDIAN_BIG}
  Result := SwapBytes32(V);
  {$ELSE}
  Result := V;
  {$ENDIF}
end;

end.
