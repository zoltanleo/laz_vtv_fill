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

  DataLoadingMsg = 'Data is loading, please wait...';
  NoChildRecords = 'Node has no children';

type
  PMyRec = ^TMyRec;
  TMyRec = packed record
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
    MDS_full: TMemDataset;
    VST: TLazVirtualStringTree;
    MDS_root_full: TMemDataset;
    MDS_root_part: TMemDataset;
    StatusBar1: TStatusBar;
    procedure Button1Click(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure MDS_root_partFilterRecord(DataSet: TDataSet; var Accept: Boolean);
    procedure VSTAddToSelection(Sender: TBaseVirtualTree; Node: PVirtualNode);
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
    FMyThr: TMyThread;
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
      VST.RootNodeCount:= MDS_root_full.RecordCount;
    finally
      VST.EndUpdate;
      VST.ScrollIntoView(aNode,True);
      VST.AddToSelection(aNode);
    end;

    endTick:= GetTickCount64;

    StatusBar1.Panels[1].Text:= Format('Executing time of inserting %d records into the VST is %d msec',
                                       [MDS_root_full.RecordCount,(endTick - startTick)]);
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

    //get all records
    FexecSQL.ExecQuery;

    Form1.InitMDS(Form1.MDS_full);

    while not FexecSQL.Eof do
    begin
      Form1.MDS_full.AppendRecord([
      //FexecSQL.FieldByName('ID').AsInteger,
      //FexecSQL.FieldByName('NAME').AsString,
      //FexecSQL.FieldByName('ID_PARENT').AsString,
      FexecSQL.Fields[0].AsInteger,
      FexecSQL.Fields[1].AsString,
      FexecSQL.Fields[2].AsString
      ]);
      FexecSQL.Next;
    end;

    //get all root records only
    with Form1 do
    begin
      InitMDS(MDS_root_full);
      MDS_full.First;

      while not MDS_full.EOF do
      begin
        if (MDS_full.Fields[2].AsInteger = 0) then
          MDS_root_full.AppendRecord([
                      MDS_full.Fields[0].AsInteger,//ID
                      MDS_full.Fields[1].AsString,//NAME
                      MDS_full.Fields[2].AsInteger//ID_PARENT
                                      ]);
        MDS_full.Next;
      end;
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
    Database:= Fdbase;
    Transaction:= FTrans;
    SQL.Text:= FprmRec.SQLText;
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
  ChExecSQL: TIBSQL = nil;
  startTick: PtrInt = 0;
  endTick: PtrInt = 0;
  i: Integer;
  //MyThr: TMyThread = nil;
  prmRec: TParamRec;
begin
  for i:= 0 to Pred(StatusBar1.Panels.Count) do
    StatusBar1.Panels[i].Text:= '';

  if not IBDatabase1.Connected then IBDatabase1.Connected:= True;
  ExecSQL:= TIBSQL.Create(Self);
  ChExecSQL:= TIBSQL.Create(Self);
  MDS_root_part.Active:= True;
  TreeSrc:= tsPartial;
  try
    try
      startTick:= GetTickCount64;
      IBTransaction1.StartTransaction;

      with ExecSQL do
      begin
        SQL.Text:= 'SELECT ID, NAME, ID_PARENT FROM TEST WHERE (ID_PARENT = 0) ORDER BY ID';
        Database:= IBDatabase1;
        Transaction:= IBTransaction1;
        ExecQuery;
      end;
        InitMDS(MDS_root_part);

        i:= 0;
        //while not Eof do
        while (ExecSQL.RecordCount <= MinCount) do
        begin
          Inc(i);
          MDS_root_part.AppendRecord([
                                  ExecSQL.FieldByName('ID').AsInteger,
                                  ExecSQL.FieldByName('NAME').AsString
                                  ]);
          ExecSQL.Next;
        end;

      endTick:= GetTickCount64;

      StatusBar1.Panels[0].Text:= Format('Execute time for selecting %d record is %d ms',
                        [MDS_root_part.RecordCount,(endTick - startTick)]);
      StatusBar1.Panels[0].Width:= StatusBar1.Canvas.TextWidth(StatusBar1.Panels[0].Text)
                          + StatusBar1.Canvas.TextWidth('WW');

      startTick:= GetTickCount64;
      VST.BeginUpdate;
      try
        VST.Clear;
        VST.RootNodeCount:= MDS_root_part.RecordCount;
      finally
        VST.EndUpdate;
        endTick:= GetTickCount64;
      end;

      StatusBar1.Panels[1].Text:= Format('Execute time for inserting to VST %d record is %d ms',
                        [VST.RootNodeCount, endTick - startTick ]);
      StatusBar1.Panels[1].Width:= StatusBar1.Canvas.TextWidth(StatusBar1.Panels[1].Text)
                          + StatusBar1.Canvas.TextWidth('WW');



      ExecSQL.SQL.Text:= 'SELECT COUNT (ID) CNT FROM TEST';
      ExecSQL.ExecQuery;
      if (ExecSQL.FieldByName('CNT').AsInteger > MinCount) then
      begin
        with prmRec do
        begin
          ConnectStr:= ConnStr;
          LibraryName:= LibName;
          UsrName:= Usr;
          PassWD:= PWDStr;
          SQLText:= 'SELECT ID, NAME, ID_PARENT FROM TEST ORDER BY ID';
        end;

        FMyThr:= TMyThread.Create(True,@prmRec);
        FMyThr.Start;
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
    FreeAndNil(ChExecSQL);
    FreeAndNil(ExecSQL);
  end;

end;

procedure TForm1.FormCreate(Sender: TObject);
begin
  TreeSrc:= tsPartial;
  FMyThr:= nil;

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

procedure TForm1.MDS_root_partFilterRecord(DataSet: TDataSet; var Accept: Boolean
  );
begin
  //Accept:= (DataSet.Fields[1].AsInteger > 20) and (DataSet.Fields[1].AsInteger < 40);
end;

procedure TForm1.VSTAddToSelection(Sender: TBaseVirtualTree; Node: PVirtualNode
  );
begin
  Caption:= 'Parent.Index = ' + IntToStr((Node^.Parent)^.Index);
end;

procedure TForm1.VSTExpanding(Sender: TBaseVirtualTree;
  Node: PVirtualNode; var Allowed: Boolean);
var
  ChNode: PVirtualNode = nil;
  NodeData: PMyRec = nil;
  ParentID: PtrInt = 0;
begin
  if (Node^.ChildCount > 0) then VST.DeleteChildren(Node);

  case TreeSrc of
    tsPartial:
      begin
        ChNode:= VST.AddChild(Node);
        NodeData:= VST.GetNodeData(ChNode);
        NodeData^.ID:= 0;
        NodeData^.Name:= DataLoadingMsg;
      end;
    tsFull:
      begin
        NodeData:= VST.GetNodeData(Node);
        ParentID:= NodeData^.ID;//get ID of Parent Node

        MDS_full.First;
        while not MDS_full.EOF do
        begin
          if (MDS_full.Fields[2].AsInteger = ParentID) then
          begin
            ChNode:= VST.AddChild(Node);
            NodeData:= VST.GetNodeData(ChNode);
            NodeData^.ID:= MDS_full.Fields[0].AsInteger;
            NodeData^.Name:= MDS_full.Fields[1].AsString;
          end;
          MDS_full.Next;
        end;

        if (Node^.ChildCount = 0) then
        begin
          ChNode:= VST.AddChild(Node);
          NodeData:= VST.GetNodeData(ChNode);
          NodeData^.ID:= 0;
          NodeData^.Name:= NoChildRecords;
        end;
      end;
  end;
  //if (vsHasChildren in Node^.States) and (Node^.ChildCount = 0) then
  //VST.AddChild(Node);
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
  NodeData: PMyRec = nil;
begin
  case TreeSrc of
    tsPartial: MDS:= MDS_root_part;
    tsFull: MDS:= MDS_root_full;
  end;

  if (vsHasChildren in Node^.States) then
    begin
      MDS.RecNo:= Succ(Node^.Index);

      NodeData:= VST.GetNodeData(Node);
      NodeData^.ID:= MDS.Fields[0].AsInteger;

      case Column of
        0: CellText:= IntToStr(NodeData^.ID);//CellText:= MDS.Fields[0].AsString;
        1: CellText:= MDS.Fields[1].AsString;
      end;
    end
  else
    begin
      NodeData:= VST.GetNodeData(Node);
      case Column of
        0: CellText:= IntToStr(NodeData^.ID);
        1: CellText:= NodeData^.Name;
      end;
    end
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
    FieldDefs.Add('ID',ftInteger);
    FieldDefs.Add('NAME',ftString,20);
    FieldDefs.Add('ID_PARENT',ftInteger);
    CreateTable;
    Active:= True;
    Filtered:= False;
  end;
end;

end.

