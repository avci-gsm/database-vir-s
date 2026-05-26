unit uThreadPool;

interface

uses
  SysUtils, Classes, SyncObjs, Generics.Collections, uStatus;

type
  TPoolTask = reference to function: TBrokkrStatus;

  TBrokkrThreadPool = class
  private
    FWorkers: TList<TThread>;
    FQueue: TThreadList<TPoolTask>;
    FEvent: TEvent;
    FStopping: Boolean;
    FCancelFlag: Integer;
    FActiveCount: Integer;
    FLock: TCriticalSection;
    FFirstError: TBrokkrStatus;
    FHasError: Boolean;
    procedure WorkerProc;
  public
    constructor Create(ThreadCount: Integer);
    destructor Destroy; override;

    function Submit(Task: TPoolTask): TBrokkrStatus;
    procedure RequestCancel;
    function Wait: TBrokkrStatus;
    procedure Stop;
    function Cancelled: Boolean;
  end;

implementation

type
  TWorkerThread = class(TThread)
  private
    FPool: TBrokkrThreadPool;
  protected
    procedure Execute; override;
  public
    constructor Create(APool: TBrokkrThreadPool);
  end;

{ TWorkerThread }

constructor TWorkerThread.Create(APool: TBrokkrThreadPool);
begin
  FPool := APool;
  FreeOnTerminate := False;
  inherited Create(False);
end;

procedure TWorkerThread.Execute;
begin
  FPool.WorkerProc;
end;

{ TBrokkrThreadPool }

constructor TBrokkrThreadPool.Create(ThreadCount: Integer);
var
  I: Integer;
begin
  inherited Create;
  FWorkers := TList<TThread>.Create;
  FQueue := TThreadList<TPoolTask>.Create;
  FEvent := TEvent.Create(nil, False, False, '');
  FLock := TCriticalSection.Create;
  FStopping := False;
  FCancelFlag := 0;
  FActiveCount := 0;
  FHasError := False;
  FFirstError := TBrokkrStatus.OK;

  for I := 0 to ThreadCount - 1 do
    FWorkers.Add(TWorkerThread.Create(Self));
end;

destructor TBrokkrThreadPool.Destroy;
begin
  Stop;
  FWorkers.Free;
  FQueue.Free;
  FEvent.Free;
  FLock.Free;
  inherited;
end;

procedure TBrokkrThreadPool.WorkerProc;
var
  Task: TPoolTask;
  List: TList<TPoolTask>;
  HasTask: Boolean;
  St: TBrokkrStatus;
begin
  while not FStopping do
  begin
    HasTask := False;
    Task := nil;

    List := FQueue.LockList;
    try
      if List.Count > 0 then
      begin
        Task := List[0];
        List.Delete(0);
        HasTask := True;
        TInterlocked.Increment(FActiveCount);
      end;
    finally
      FQueue.UnlockList;
    end;

    if HasTask then
    begin
      try
        St := Task();
        if not St.IsOK then
        begin
          FLock.Enter;
          try
            if not FHasError then
            begin
              FHasError := True;
              FFirstError := St;
            end;
          finally
            FLock.Leave;
          end;
        end;
      except
        on E: Exception do
        begin
          FLock.Enter;
          try
            if not FHasError then
            begin
              FHasError := True;
              FFirstError := TBrokkrStatus.Fail(E.Message);
            end;
          finally
            FLock.Leave;
          end;
        end;
      end;
      TInterlocked.Decrement(FActiveCount);
    end
    else
      FEvent.WaitFor(100);
  end;
end;

function TBrokkrThreadPool.Submit(Task: TPoolTask): TBrokkrStatus;
var
  List: TList<TPoolTask>;
begin
  if FStopping then
    Exit(TBrokkrStatus.Fail('Pool is stopping'));

  List := FQueue.LockList;
  try
    List.Add(Task);
  finally
    FQueue.UnlockList;
  end;
  FEvent.SetEvent;
  Result := TBrokkrStatus.OK;
end;

procedure TBrokkrThreadPool.RequestCancel;
begin
  TInterlocked.Exchange(FCancelFlag, 1);
end;

function TBrokkrThreadPool.Wait: TBrokkrStatus;
var
  List: TList<TPoolTask>;
  Empty: Boolean;
begin
  repeat
    List := FQueue.LockList;
    try
      Empty := (List.Count = 0) and (FActiveCount = 0);
    finally
      FQueue.UnlockList;
    end;
    if not Empty then
      Sleep(50);
  until Empty or FStopping;

  FLock.Enter;
  try
    if FHasError then
      Result := FFirstError
    else
      Result := TBrokkrStatus.OK;
  finally
    FLock.Leave;
  end;
end;

procedure TBrokkrThreadPool.Stop;
var
  W: TThread;
begin
  FStopping := True;
  FEvent.SetEvent;
  for W in FWorkers do
  begin
    W.WaitFor;
    W.Free;
  end;
  FWorkers.Clear;
end;

function TBrokkrThreadPool.Cancelled: Boolean;
begin
  Result := (TInterlocked.Read(FCancelFlag) <> 0);
end;

end.
