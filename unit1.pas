unit Unit1;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, memds, DB, Forms, Controls, Graphics, Dialogs, StdCtrls,
  DBGrids, Spin, ComCtrls, ExtCtrls, laz.VirtualTrees, LazUTF8, IBDatabase,
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
    ID: PtrInt;
    Name: String;
  end;

  { TMyThread }

  TMyThread = class(TThread)
  private
    Fdbase: TIBDataBase;
    FTrans: TIBTransaction;
    FexecSQL: TIBSQL;
    FMDS_thread: TMemDataset;
    procedure FillExtVST;
    procedure AddNodeToExtVST;
  protected
    procedure Execute; override;
  public
    constructor Create(CreateSuspended: Boolean);
    destructor Destroy; override;
  published
  end;

  { TForm1 }

  TForm1 = class(TForm)
    Button1: TButton;
    Button2: TButton;
    Button3: TButton;
    IBDatabase1: TIBDatabase;
    IBEvents1: TIBEvents;
    IBTransaction1: TIBTransaction;
    Splitter1: TSplitter;
    VST_full: TLazVirtualStringTree;
    MDS_full: TMemDataset;
    VST_partial: TLazVirtualStringTree;
    MDS_partial: TMemDataset;
    SpinEdit1: TSpinEdit;
    StatusBar1: TStatusBar;
    procedure Button1Click(Sender: TObject);
    procedure Button2Click(Sender: TObject);
    procedure Button3Click(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure VST_fullFreeNode(Sender: TBaseVirtualTree; Node: PVirtualNode);
    procedure VST_fullGetNodeDataSize(Sender: TBaseVirtualTree;
      var NodeDataSize: Integer);
    procedure VST_fullGetText(Sender: TBaseVirtualTree; Node: PVirtualNode;
      Column: TColumnIndex; TextType: TVSTTextType; var CellText: String);
    procedure VST_partialFreeNode(Sender: TBaseVirtualTree;
      Node: PVirtualNode);
    procedure VST_partialGetNodeDataSize(Sender: TBaseVirtualTree;
      var NodeDataSize: Integer);
    procedure VST_partialGetText(Sender: TBaseVirtualTree;
      Node: PVirtualNode; Column: TColumnIndex; TextType: TVSTTextType;
      var CellText: String);
  private

  public
    procedure FillTree;
  end;

const
  MinCount = 100000;
var
  Form1: TForm1;

implementation

{$R *.lfm}

{ TMyThread }

procedure TMyThread.FillExtVST;
var
  selNode: PVirtualNode = nil;
  aNode: PVirtualNode = nil;
  aNodeData: PMyRec = nil;
  id: PtrInt = 0;
  startTick, endTick: QWord;
  RecCnt: PtrInt = 0;
begin
  startTick:= GetTickCount64;

  Form1.VST_full.Visible:= False;
  Form1.VST_full.BeginUpdate;
  try
    Form1.VST_full.Clear;

    while not FexecSQL.Eof do
    begin
      aNode:= Form1.VST_full.AddChild(nil);
      if Assigned(aNode) then aNodeData:= Form1.VST_full.GetNodeData(aNode);

      if Assigned(aNodeData) then
      begin
        aNodeData:= Form1.VST_full.GetNodeData(aNode);
        aNodeData^.ID:= FexecSQL.FieldByName('ID').AsInteger;
        aNodeData^.Name:= FexecSQL.FieldByName('NAME').AsString;
        Form1.VST_full.AddChild(aNode);
      end;

      FexecSQL.Next;
    end;

    RecCnt:= FexecSQL.RecordCount;

    selNode:= Form1.VST_partial.GetFirstSelected(True);
    if Assigned(selNode)
      then id:= PMyRec(Form1.VST_partial.GetNodeData(selNode))^.ID
      else id:= PMyRec(Form1.VST_partial.GetNodeData(Form1.VST_partial.GetFirst))^.ID;

    aNode:= Form1.VST_full.GetFirst;

    while Assigned(aNode) do
    begin
      aNodeData:= Form1.VST_full.GetNodeData(aNode);

      if Assigned(aNodeData) then
        if (aNodeData^.ID = id) then Break;

      aNode:= aNode^.NextSibling;
    end;
  finally
    Form1.VST_full.Visible:= True;
    Form1.VST_full.EndUpdate;
    Form1.VST_full.AddToSelection(aNode);
    Form1.VST_full.ScrollIntoView(aNode,True);
  end;
  endTick:= GetTickCount64;

  with Form1 do
  begin
    StatusBar1.Panels[1].Text:= Format('Executing time of inserting %d records into the VST_full is %d msec',
                                       [RecCnt,(endTick - startTick)]);
    StatusBar1.Panels[1].Width:= StatusBar1.Canvas.TextWidth(StatusBar1.Panels[1].Text)
                        + StatusBar1.Canvas.TextWidth('W');
  end;
end;

procedure TMyThread.AddNodeToExtVST;
var
  aNode: PVirtualNode = nil;
  aNodeData: PMyRec = nil;
begin
  with Form1 do
  begin
    //VST_full.BeginUpdate;
    try
      aNode:= VST_full.AddChild(nil);
      aNodeData:= VST_full.GetNodeData(aNode);

      if Assigned(aNodeData) then
      begin
        aNodeData^.ID:= FexecSQL.FieldByName('ID').AsInteger;
        aNodeData^.Name:= FexecSQL.FieldByName('NAME').AsString;
        VST_full.AddChild(aNode);
      end;

    finally
      //VST_full.EndUpdate;
      //VST_full.ScrollIntoView(aNode,True);
    end;
  end;
end;

procedure TMyThread.Execute;
begin
  try
    if not Fdbase.Connected then Fdbase.Connected:= True;

    FMDS_thread.Active:= True;
    FMDS_thread.Clear(False);

    FTrans.StartTransaction;

    FexecSQL.ExecQuery;

    Form1.VST_full.Clear;

    while not FexecSQL.Eof do
    begin
      Synchronize(@AddNodeToExtVST);
      Sleep(1);
      FexecSQL.Next;
    end;

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

constructor TMyThread.Create(CreateSuspended: Boolean);
begin
  inherited Create(CreateSuspended);

  Priority:= tpNormal;
  FreeOnTerminate:= True;
  Fdbase:= TIBDataBase.Create(nil);
  FTrans:= TIBTransaction.Create(nil);
  FexecSQL:= TIBSQL.Create(nil);
  FMDS_thread:= TMemDataset.Create(nil);
  FMDS_thread.FieldDefs.Add('ID',ftInteger);
  FMDS_thread.FieldDefs.Add('NAME',ftString,20);

  with Fdbase do
  begin
    FirebirdLibraryPathName:= LibName;
    DatabaseName:= ConnStr;
    DefaultTransaction:=  FTrans;
    Params.Add(Usr);
    Params.Add(PWDStr);
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
    SQL.Text:= 'SELECT ID, NAME FROM TEST';
    Database:= Fdbase;
    Transaction:= FTrans;
  end;
end;

destructor TMyThread.Destroy;
begin
  FMDS_thread.Free;
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
begin
  Button1.Enabled:= False;
  Button2.Enabled:= False;

  for i:= 0 to Pred(StatusBar1.Panels.Count) do
    StatusBar1.Panels[i].Text:= '';

  if not IBDatabase1.Connected then IBDatabase1.Connected:= True;
  ExecSQL:= TIBSQL.Create(Self);

  try
    try
      startTick:= GetTickCount64;
      IBTransaction1.StartTransaction;
      with ExecSQL do
      begin
        SQL.Text:= 'SELECT ID, NAME FROM TEST';
        Database:= IBDatabase1;
        Transaction:= IBTransaction1;
        ExecQuery;

        MDS_partial.Clear(False);

        while not Eof do
        begin
          MDS_partial.AppendRecord([FieldByName('ID').AsInteger,FieldByName('NAME').AsString]);
          Next;
        end;
      end;
      IBTransaction1.Commit;

      endTick:= GetTickCount64;

      Caption:= Format('Execute time for selecting %d record is %d sec (Full Fetch)',
                        [MDS_partial.RecordCount,(endTick - startTick) div 1000]);

      FillTree;
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
    Button1.Enabled:= True;
    Button2.Enabled:= True;
  end;

end;

procedure TForm1.Button2Click(Sender: TObject);
var
  ExecSQL: TIBSQL = Nil;
  startTick: PtrInt = 0;
  endTick: PtrInt = 0;
  MyThread: TMyThread = nil;
  i: Integer;
  rNode: PVirtualNode = nil;
  rNodeData: PMyRec = nil;
begin
  //Button2.Enabled:= False;
  //Button1.Enabled:= False;
  //VST_partial.Visible:= True;

  for i:= 0 to Pred(StatusBar1.Panels.Count) do
    StatusBar1.Panels[i].Text:= '';

  if not IBDatabase1.Connected then IBDatabase1.Connected:= True;

  ExecSQL:= TIBSQL.Create(Self);

  try
    try
      startTick:= GetTickCount64;
      IBTransaction1.StartTransaction;

      ExecSQL.Database:= IBDatabase1;
      ExecSQL.Transaction:= IBTransaction1;

      //ExecSQL.SQL.Text:= 'SELECT COUNT(ID) CNT FROM TEST';
      //ExecSQL.ExecQuery;
      //
      //if (ExecSQL.FieldByName('CNT').AsInteger > MinCount) then
      //begin
      //  MyThread:= TMyThread.Create(True);
      //  MyThread.Start;
      //end;

      ExecSQL.SQL.Text:= 'SELECT ID, NAME FROM TEST';
      ExecSQL.ExecQuery;

      VST_partial.BeginUpdate;
      try
        VST_partial.Clear;
        //while not Eof do
        while (ExecSQL.RecordCount < Succ(MinCount)) do
        begin
          rNode:= VST_partial.AddChild(nil);
          rNodeData:= VST_partial.GetNodeData(rNode);
          rNodeData^.ID:= ExecSQL.FieldByName('ID').AsInteger;
          rNodeData^.Name:= ExecSQL.FieldByName('NAME').AsString;
          VST_partial.AddChild(rNode);
          ExecSQL.Next;
        end;
      finally
        VST_partial.EndUpdate;
        VST_partial.ScrollIntoView(rNode,True);
        VST_partial.AddToSelection(rNode);
        VST_partial.Expanded[rNode]:= False;
      end;

      endTick:= GetTickCount64;

      StatusBar1.Panels[0].Text:= Format('Executing time of inserting %d records into the VST_partial is %d msec',
                                    [MinCount, (endTick - startTick)]);
      StatusBar1.Panels[0].Width:= StatusBar1.Canvas.TextWidth(StatusBar1.Panels[0].Text)
                        + StatusBar1.Canvas.TextWidth('W');
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
    //Button1.Enabled:= True;
    //Button2.Enabled:= True;
  end;
end;

procedure TForm1.Button3Click(Sender: TObject);
begin
  MDS_partial.RecNo:= SpinEdit1.Value;
end;

procedure TForm1.FormCreate(Sender: TObject);
begin
  //uses DB
  MDS_partial.FieldDefs.Add('ID',ftInteger);
  MDS_partial.FieldDefs.Add('NAME',ftString,20);
  MDS_partial.Active:= True;

  MDS_full.FieldDefs.Add('ID',ftInteger);
  MDS_full.FieldDefs.Add('NAME',ftString,20);
  MDS_full.Active:= True;


  with IBDatabase1 do
  begin
    FirebirdLibraryPathName:= LibName;
    DatabaseName:= ConnStr;
    Params.Add(Usr);
    Params.Add(PWDStr);
    Params.Add('lc_ctype=UTF8');
    LoginPrompt:= False;
  end;

  //VST_partial.Anchors:= VST_partial.Anchors + [akRight];
end;

procedure TForm1.VST_fullFreeNode(Sender: TBaseVirtualTree; Node: PVirtualNode);
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

procedure TForm1.VST_fullGetNodeDataSize(Sender: TBaseVirtualTree;
  var NodeDataSize: Integer);
begin
  NodeDataSize:= SizeOf(TMyRec);
end;

procedure TForm1.VST_fullGetText(Sender: TBaseVirtualTree; Node: PVirtualNode;
  Column: TColumnIndex; TextType: TVSTTextType; var CellText: String);
var
  NodeData: PMyRec;
begin
  NodeData:= TBaseVirtualTree(Sender).GetNodeData(Node);

  case Column of
    0: CellText:= IntToStr(NodeData^.ID);
    1: CellText:= NodeData^.Name;
  end;
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

procedure TForm1.VST_partialGetText(Sender: TBaseVirtualTree;
  Node: PVirtualNode; Column: TColumnIndex; TextType: TVSTTextType;
  var CellText: String);
var
  NodeData: PMyRec;
begin
  NodeData:= TBaseVirtualTree(Sender).GetNodeData(Node);

  case Column of
    0: CellText:= IntToStr(NodeData^.ID);
    1: CellText:= NodeData^.Name;
  end;
end;

procedure TForm1.FillTree;
var
  aNodeData: PMyRec = nil;
  rNode: PVirtualNode = nil;
  startTick: PtrInt = 0;
  endTick: PtrInt = 0;
begin
  VST_partial.BeginUpdate;
  try
    VST_partial.Clear;
    if MDS_partial.IsEmpty then Exit;

    startTick:= GetTickCount64;

    MDS_partial.First;

    while not MDS_partial.EOF do
    begin
      rNode:= VST_partial.AddChild(nil);
      aNodeData:= VST_partial.GetNodeData(rNode);
      aNodeData^.ID:= MDS_partial.FieldByName('ID').AsInteger;
      aNodeData^.Name:= MDS_partial.FieldByName('NAME').AsString;
      VST_partial.AddChild(rNode);
      MDS_partial.Next;
    end;
  finally
    VST_partial.EndUpdate;
    VST_partial.ScrollIntoView(rNode,True);
    VST_partial.AddToSelection(rNode);
    VST_partial.Expanded[rNode]:= False;
    endTick:= GetTickCount64;

    StatusBar1.Panels[0].Text:= Format('Executing time of inserting %d records into the VST is %d sec',
                                  [MDS_partial.RecordCount, (endTick - startTick) div 1000]);
    StatusBar1.Panels[0].Width:= StatusBar1.Canvas.TextWidth(StatusBar1.Panels[0].Text)
                      + StatusBar1.Canvas.TextWidth('W');
  end;
end;

end.

