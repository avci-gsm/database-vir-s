unit uStatus;

interface

uses
  SysUtils;

type
  EBrokkrError = class(Exception);

  TBrokkrStatus = record
  private
    FSuccess: Boolean;
    FError: string;
  public
    class function OK: TBrokkrStatus; static;
    class function Fail(const Msg: string): TBrokkrStatus; static;
    class function Failf(const Fmt: string; const Args: array of const): TBrokkrStatus; static;

    function IsOK: Boolean;
    function Error: string;

    procedure RaiseIfFailed;
  end;

  TBrokkrResult<T> = record
  private
    FSuccess: Boolean;
    FError: string;
    FValue: T;
  public
    class function OK(const AValue: T): TBrokkrResult<T>; static;
    class function Fail(const Msg: string): TBrokkrResult<T>; static;

    function IsOK: Boolean;
    function Error: string;
    function Value: T;

    procedure RaiseIfFailed;
  end;

implementation

{ TBrokkrStatus }

class function TBrokkrStatus.OK: TBrokkrStatus;
begin
  Result.FSuccess := True;
  Result.FError := '';
end;

class function TBrokkrStatus.Fail(const Msg: string): TBrokkrStatus;
begin
  Result.FSuccess := False;
  Result.FError := Msg;
end;

class function TBrokkrStatus.Failf(const Fmt: string; const Args: array of const): TBrokkrStatus;
begin
  Result.FSuccess := False;
  Result.FError := Format(Fmt, Args);
end;

function TBrokkrStatus.IsOK: Boolean;
begin
  Result := FSuccess;
end;

function TBrokkrStatus.Error: string;
begin
  Result := FError;
end;

procedure TBrokkrStatus.RaiseIfFailed;
begin
  if not FSuccess then
    raise EBrokkrError.Create(FError);
end;

{ TBrokkrResult<T> }

class function TBrokkrResult<T>.OK(const AValue: T): TBrokkrResult<T>;
begin
  Result.FSuccess := True;
  Result.FError := '';
  Result.FValue := AValue;
end;

class function TBrokkrResult<T>.Fail(const Msg: string): TBrokkrResult<T>;
begin
  Result.FSuccess := False;
  Result.FError := Msg;
  Result.FValue := Default(T);
end;

function TBrokkrResult<T>.IsOK: Boolean;
begin
  Result := FSuccess;
end;

function TBrokkrResult<T>.Error: string;
begin
  Result := FError;
end;

function TBrokkrResult<T>.Value: T;
begin
  Result := FValue;
end;

procedure TBrokkrResult<T>.RaiseIfFailed;
begin
  if not FSuccess then
    raise EBrokkrError.Create(FError);
end;

end.
