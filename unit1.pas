unit Unit1;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, memds, DB, Forms, Controls, Graphics, Dialogs, StdCtrls,
  DBGrids, ComCtrls, ExtCtrls, laz.VirtualTrees, LazUTF8, IBDatabase,
  IBSQL, IBEvents;

const

  {$IFDEF MSWINDOWS}
  ConnStr = '127.0.0.1/31064:c:\proj\vtv_fill\base\TEST.FDB';
  LibName = 'd:\Portable_program\Firebird_server\Firebird_3_0_10_x64\fbclient.dll';
  PWDStr = 'password=cooladmin';
  Usr = 'user_name=SYSDBA';
  {$ELSE}
    {$IFDEF DARWIN}
    ConnStr = '';
    LibName = '';
    {$ELSE}
    ConnStr = '';
    LibName = '';
    {$ENDIF}
  {$ENDIF}

type
  PMyRec = ^TMyRec;
  TMyRec = packed record
    ID_INC: PtrInt;
    ID: PtrInt;
    Name: String;
  end;

  TTreeSrc = (tsPartial, tsFull);

  PParamRec = ^TParamRec;
  TParamRec = packed record
    ConnectStr: String;
    LibraryName: String;
    SQLText: String;
    UsrName: String;
    PassWD: String;
  end;

  { TMyThread }

  TMyThread = class(TThread)
  private
    Fdbase: TIBDataBase;
    FTrans: TIBTransaction;
    FexecSQL: TIBSQL;
    FprmRec: TParamRec;
    FStartTick: QWord;
    FEndTick: QWord;
    procedure FillExtVST;
    procedure ShowExecTime;
  protected
    procedure Execute; override;
  public
    constructor Create(CreateSuspended: Boolean; prmRec: PParamRec);
    destructor Destroy; override;
  published
  end;

  { TForm1 }

  TForm1 = class(TForm)
    Button1: TButton;
    IBDatabase1: TIBDatabase;
    IBEvents1: TIBEvents;
    IBTransaction1: TIBTransaction;
    VST: TLazVirtualStringTree;
    MDS_full: TMemDataset;
    MDS_partial: TMemDataset;
    StatusBar1: TStatusBar;
    procedure Button1Click(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure MDS_partialFilterRecord(DataSet: TDataSet; var Accept: Boolean);
    procedure VSTExpanding(Sender: TBaseVirtualTree; Node: PVirtualNode;
      var Allowed: Boolean);
    procedure VSTFreeNode(Sender: TBaseVirtualTree; Node: PVirtualNode);
    procedure VSTGetNodeDataSize(Sender: TBaseVirtualTree;
      var NodeDataSize: Integer);
    procedure VSTGetText(Sender: TBaseVirtualTree; Node: PVirtualNode;
      Column: TColumnIndex; TextType: TVSTTextType; var CellText: String);
    procedure VSTInitNode(Sender: TBaseVirtualTree; ParentNode,
      Node: PVirtualNode; var InitialStates: TVirtualNodeInitStates);
    procedure VST_partialFreeNode(Sender: TBaseVirtualTree;
      Node: PVirtualNode);
    procedure VST_partialGetNodeDataSize(Sender: TBaseVirtualTree;
      var NodeDataSize: Integer);
  private
    FTreeSrc: TTreeSrc;
  public
    procedure InitMDS(Sender: TMemDataset);
    property TreeSrc: TTreeSrc read FTreeSrc write FTreeSrc;
  end;

const
  MinCount = 1000;
var
  Form1: TForm1;

implementation

{$R *.lfm}

{ TMyThread }

procedure TMyThread.FillExtVST;
var
  startTick, endTick: QWord;
  aNode: PVirtualNode = Nil;
begin
  with Form1 do
  begin
    startTick:= GetTickCount64;
    TreeSrc:= tsFull;
    aNode:= VST.GetFirstSelected;
    if not Assigned(aNode) then aNode:= VST.GetFirst;

    VST.BeginUpdate;

    try
      VST.Clear;
      VST.RootNodeCount:= MDS_full.RecordCount;
    finally
      VST.EndUpdate;
      VST.ScrollIntoView(aNode,True);
      VST.AddToSelection(aNode);
    end;

    endTick:= GetTickCount64;

    StatusBar1.Panels[1].Text:= Format('Executing time of inserting %d records into the VST_full is %d msec',
                                       [MDS_full.RecordCount,(endTick - startTick)]);
    StatusBar1.Panels[1].Width:= StatusBar1.Canvas.TextWidth(StatusBar1.Panels[1].Text)
                        + StatusBar1.Canvas.TextWidth('W');
  end;
end;

procedure TMyThread.ShowExecTime;
begin
  with Form1 do
  begin
    StatusBar1.Panels[0].Text:= Format('Execute time for selecting %d record is %d ms',
                      [MDS_full.RecordCount,(FEndTick - FStartTick)]);
    StatusBar1.Panels[0].Width:= StatusBar1.Canvas.TextWidth(StatusBar1.Panels[0].Text)
                        + StatusBar1.Canvas.TextWidth('WW');
  end;
end;

procedure TMyThread.Execute;
begin
  try
    if not Fdbase.Connected then Fdbase.Connected:= True;
    FStartTick:= GetTickCount64;
    FTrans.StartTransaction;
    FexecSQL.ExecQuery;

    Form1.InitMDS(Form1.MDS_full);

    while not FexecSQL.Eof do
    begin
      Form1.MDS_full.AppendRecord([
      FexecSQL.RecordCount,
      FexecSQL.FieldByName('ID').AsInteger,
      FexecSQL.FieldByName('NAME').AsString
      ]);
      FexecSQL.Next;
    end;

    FEndTick:= GetTickCount64;
    Queue(@ShowExecTime);
    Queue(@FillExtVST);
    FTrans.Commit;
  except
    on E:Exception do
    begin
      FTrans.Rollback;
      {$IFDEF MSWINDOWS}
      ShowMessage(WinCPToUTF8(E.Message));
      {$ELSE}
      ShowMessage(E.Message);
      {$ENDIF}
    end;
  end;
end;

constructor TMyThread.Create(CreateSuspended: Boolean; prmRec: PParamRec);
begin
  inherited Create(CreateSuspended);

  Priority:= tpNormal;
  FreeOnTerminate:= True;
  Fdbase:= TIBDataBase.Create(nil);
  FTrans:= TIBTransaction.Create(nil);
  FexecSQL:= TIBSQL.Create(nil);
  FprmRec:= prmRec^;

  with Fdbase do
  begin
    FirebirdLibraryPathName:= FprmRec.LibraryName;
    DatabaseName:= FprmRec.ConnectStr;
    DefaultTransaction:=  FTrans;
    Params.Add(FprmRec.UsrName);
    Params.Add(FprmRec.PassWD);
    Params.Add('lc_ctype=UTF8');
    LoginPrompt:= False;
  end;

  with FTrans do
  begin
    Params.Add('read');
    Params.Add('read_committed');
    Params.Add('rec_version');
    Params.Add('nowait');
    DefaultDatabase:= Fdbase;
  end;

  with FexecSQL do
  begin
    SQL.Text:= prmRec^.SQLText;
    Database:= Fdbase;
    Transaction:= FTrans;
  end;
end;

destructor TMyThread.Destroy;
begin
  FexecSQL.Free;
  FTrans.Free;
  Fdbase.Free;
  inherited Destroy;
end;

{ TForm1 }

procedure TForm1.Button1Click(Sender: TObject);
var
  ExecSQL: TIBSQL = Nil;
  startTick: PtrInt = 0;
  endTick: PtrInt = 0;
  i: Integer;
  MyThr: TMyThread = nil;
  prmRec: TParamRec;
begin
  for i:= 0 to Pred(StatusBar1.Panels.Count) do
    StatusBar1.Panels[i].Text:= '';

  if not IBDatabase1.Connected then IBDatabase1.Connected:= True;
  ExecSQL:= TIBSQL.Create(Self);
  MDS_partial.Active:= True;
  TreeSrc:= tsPartial;
  try
    try
      startTick:= GetTickCount64;
      IBTransaction1.StartTransaction;

      with ExecSQL do
      begin
        SQL.Text:= 'SELECT ID, NAME FROM TEST WHERE (ID_PARENT = 0) ORDER BY ID';
        Database:= IBDatabase1;
        Transaction:= IBTransaction1;
        ExecQuery;

        //MDS_partial.Clear(False);
        InitMDS(MDS_partial);

        //while not Eof do
        while (RecordCount <= MinCount) do
        begin
          MDS_partial.AppendRecord([RecordCount, FieldByName('ID').AsInteger,FieldByName('NAME').AsString]);
          Next;
        end;
      end;


      endTick:= GetTickCount64;

      StatusBar1.Panels[0].Text:= Format('Execute time for selecting %d record is %d ms',
                        [MDS_partial.RecordCount,(endTick - startTick)]);
      StatusBar1.Panels[0].Width:= StatusBar1.Canvas.TextWidth(StatusBar1.Panels[0].Text)
                          + StatusBar1.Canvas.TextWidth('WW');

      startTick:= GetTickCount64;
      VST.BeginUpdate;
      try
        VST.Clear;
        VST.RootNodeCount:= MDS_partial.RecordCount;
      finally
        VST.EndUpdate;
        endTick:= GetTickCount64;
      end;

      StatusBar1.Panels[1].Text:= Format('Execute time for inserting to VST %d record is %d ms',
                        [VST.RootNodeCount, endTick - startTick ]);
      StatusBar1.Panels[1].Width:= StatusBar1.Canvas.TextWidth(StatusBar1.Panels[1].Text)
                          + StatusBar1.Canvas.TextWidth('WW');

      with prmRec do
      begin
        ConnectStr:= ConnStr;
        LibraryName:= LibName;
        UsrName:= Usr;
        PassWD:= PWDStr;
        SQLText:= ExecSQL.SQL.Text;
      end;

      ExecSQL.SQL.Text:= 'SELECT COUNT (ID) CNT FROM TEST';
      ExecSQL.ExecQuery;
      if (ExecSQL.FieldByName('CNT').AsInteger > MinCount) then
      begin
        MyThr:= TMyThread.Create(True,@prmRec);
        MyThr.Start;
      end;

      IBTransaction1.Commit;
    except
      on E:Exception do
      begin
        IBTransaction1.Rollback;
        {$IFDEF MSWINDOWS}
        ShowMessage(WinCPToUTF8(E.Message));
        {$ELSE}
        ShowMessage(E.Message);
        {$ENDIF}
      end;
    end;
  finally
    FreeAndNil(ExecSQL);
  end;

end;

procedure TForm1.FormCreate(Sender: TObject);
begin
  //uses DB
  //MDS_partial.FieldDefs.Add('SQC',ftAutoInc);
  //MDS_partial.FieldDefs.Add('ID',ftInteger);
  //MDS_partial.FieldDefs.Add('NAME',ftString,20);
  //MDS_partial.Active:= True;
  //InitMDS(MDS_partial);
  //InitMDS(MDS_full);
  //MDS_full.FieldDefs.Add('SQC',ftAutoInc);
  //MDS_full.FieldDefs.Add('ID',ftInteger);
  //MDS_full.FieldDefs.Add('NAME',ftString,20);
  //MDS_full.Active:= True;

  TreeSrc:= tsPartial;

  with IBDatabase1 do
  begin
    FirebirdLibraryPathName:= LibName;
    DatabaseName:= ConnStr;
    Params.Add(Usr);
    Params.Add(PWDStr);
    Params.Add('lc_ctype=UTF8');
    LoginPrompt:= False;
  end;
end;

procedure TForm1.MDS_partialFilterRecord(DataSet: TDataSet; var Accept: Boolean
  );
begin
  Accept:= (DataSet.Fields[1].AsInteger > 20) and (DataSet.Fields[1].AsInteger < 40);
end;

procedure TForm1.VSTExpanding(Sender: TBaseVirtualTree;
  Node: PVirtualNode; var Allowed: Boolean);
begin
  if (vsHasChildren in Node^.States) and (Node^.ChildCount = 0) then
  VST.AddChild(Node);
end;

procedure TForm1.VSTFreeNode(Sender: TBaseVirtualTree; Node: PVirtualNode);
var
  NodeData: PMyRec;
begin
  NodeData:= TBaseVirtualTree(Sender).GetNodeData(Node);

  if Assigned(NodeData) then
  begin
    NodeData^.ID:= 0;
    NodeData^.Name:= '';
  end;
end;

procedure TForm1.VSTGetNodeDataSize(Sender: TBaseVirtualTree;
  var NodeDataSize: Integer);
begin
  NodeDataSize:= SizeOf(TMyRec);
end;

procedure TForm1.VSTGetText(Sender: TBaseVirtualTree; Node: PVirtualNode;
  Column: TColumnIndex; TextType: TVSTTextType; var CellText: String);
var
  MDS: TMemDataset = nil;
begin
  case TreeSrc of
    tsPartial: MDS:= MDS_partial;
    tsFull: MDS:= MDS_full;
  end;

  if ((vsHasChildren in Node^.States)) then
    begin
      MDS.RecNo:= Succ(Node^.Index);
      case Column of
        0: CellText:= MDS.Fields[1].AsString;
        1: CellText:= MDS.Fields[2].AsString;
      end;
    end
  //else
  //  begin
  //    NodeData:= VST.GetNodeData(Node);
  //    case Column of
  //      0: CellText:= IntToStr(NodeData^.ID);
  //      1: CellText:= NodeData^.Name;
  //    end;
  //  end
    ;
end;

procedure TForm1.VSTInitNode(Sender: TBaseVirtualTree; ParentNode,
  Node: PVirtualNode; var InitialStates: TVirtualNodeInitStates);
begin
  if not Assigned(ParentNode) then InitialStates:= [ivsHasChildren];
end;

procedure TForm1.VST_partialFreeNode(Sender: TBaseVirtualTree;
  Node: PVirtualNode);
var
  NodeData: PMyRec;
begin
  NodeData:= TBaseVirtualTree(Sender).GetNodeData(Node);

  if Assigned(NodeData) then
  begin
    NodeData^.ID:= 0;
    NodeData^.Name:= '';
  end;
end;

procedure TForm1.VST_partialGetNodeDataSize(Sender: TBaseVirtualTree;
  var NodeDataSize: Integer);
begin
  NodeDataSize:= SizeOf(TMyRec);
end;

procedure TForm1.InitMDS(Sender: TMemDataset);
begin
  with TMemDataset(Sender) do
  begin
    if Active then Clear(True);
    FieldDefs.Add('SQC',ftInteger);
    FieldDefs.Add('ID',ftInteger);
    FieldDefs.Add('NAME',ftString,20);
    CreateTable;
    Active:= True;
    Filtered:= False;
  end;
end;

end.

