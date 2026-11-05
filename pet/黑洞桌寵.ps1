param([switch]$Pet,[switch]$MakeIcon,[switch]$SmokeTest,[string]$TransferTarget)
$ErrorActionPreference = 'Stop'
$shortcut = Join-Path ([Environment]::GetFolderPath('DesktopDirectory')) 'AI 記憶黑洞.lnk'
if (-not ($Pet -or $MakeIcon -or $SmokeTest)) {
    $created = $false
    $mutex = [Threading.Mutex]::new($true,'Local\AiMemoryBlackHole',[ref]$created)
    try {
        if (-not $created) { return }
        # 一律去掉隱藏：上次若異常結束，圖示會留在隱藏狀態，不能把它當成原始狀態記下來。
        $attributes = [IO.FileAttributes]([int][IO.File]::GetAttributes($shortcut) -band (-bnot [int][IO.FileAttributes]::Hidden))
        try {
            Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -STA -File "'+$PSCommandPath+'" -Pet') -WindowStyle Hidden -Wait
        } finally {
            if ([IO.File]::Exists($shortcut)) { [IO.File]::SetAttributes($shortcut,$attributes) }
        }
    } finally {
        if ($created) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
    return
}

Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,System.Windows.Forms
function Brush($color) { [Windows.Media.BrushConverter]::new().ConvertFromString($color) }
function Ellipse($parent,$x,$y,$width,$height,$fill,$stroke,$thickness) {
    $shape = [Windows.Shapes.Ellipse]::new()
    $shape.Width=$width; $shape.Height=$height
    if ($fill) { $shape.Fill=Brush $fill }
    if ($stroke) { $shape.Stroke=Brush $stroke; $shape.StrokeThickness=$thickness }
    [Windows.Controls.Canvas]::SetLeft($shape,$x)
    [Windows.Controls.Canvas]::SetTop($shape,$y)
    [void]$parent.Children.Add($shape)
    return $shape
}
$size=144
$canvas=[Windows.Controls.Canvas]::new()
$canvas.Width=$size; $canvas.Height=$size
$canvas.Background=[Windows.Media.Brushes]::Transparent
$random=[Random]::new(89)
$particles=New-Object 'System.Collections.Generic.List[object]'
function Add-Disk([bool]$front) {
    $layer=[Windows.Controls.Canvas]::new()
    $layer.Width=$size; $layer.Height=$size
    [void]$canvas.Children.Add($layer)
    for($i=0;$i -lt 125;$i++){
        $angle=$random.NextDouble()*6.283185
        $radius=28+44*[Math]::Pow($random.NextDouble(),1.45)
        $d=.65+$random.NextDouble()*1.65
        $color=@('#FFD291','#FFAE67','#F4804A','#9A4A32')[$random.Next(4)]
        $dot=Ellipse $layer 0 0 ($d*1.5) $d $color $null 0
        $particles.Add(@{Shape=$dot;Angle=$angle;Radius=$radius;Front=$front})
    }
}
function Render-Disk([double]$phase) {
    foreach($particle in $particles) {
        $angle=$particle.Angle+$phase*(50/$particle.Radius)
        $sin=[Math]::Sin($angle)
        $particle.Shape.Opacity=if (($sin -ge 0) -eq $particle.Front) { .5+.47*[Math]::Abs($sin) } else { 0 }
        [Windows.Controls.Canvas]::SetLeft($particle.Shape,(72+[Math]::Cos($angle)*$particle.Radius))
        [Windows.Controls.Canvas]::SetTop($particle.Shape,(72+$sin*$particle.Radius*.22))
    }
}
Add-Disk $false
foreach($ring in @(@(65,'#19E27439',5),@(61,'#36FF924E',3),@(57,'#70FF9B59',2))) {
    $offset=(144-$ring[0])/2
    [void](Ellipse $canvas $offset $offset $ring[0] $ring[0] $null $ring[1] $ring[2])
}
[void](Ellipse $canvas 45 45 54 54 '#FF070609' '#E2FFA568' 1.5)
Add-Disk $true
$canvas.RenderTransform=[Windows.Media.RotateTransform]::new(-12,72,72)
Render-Disk 0

if ($MakeIcon) {
    $canvas.Measure([Windows.Size]::new(144,144))
    $canvas.Arrange([Windows.Rect]::new(0,0,144,144))
    $bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new(144,144,96,96,[Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($canvas)
    $encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new()
    $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $stream=[IO.MemoryStream]::new()
    $encoder.Save($stream)
    $png=$stream.ToArray()
    $stream.Dispose()
    $header=[byte[]](0,0,1,0,1,0,144,144,0,0,1,0,32,0)
    $icon=$header+[BitConverter]::GetBytes([int]$png.Length)+[BitConverter]::GetBytes([int]22)+$png
    [IO.File]::WriteAllBytes((Join-Path $PSScriptRoot '黑洞.ico'),$icon)
    return
}
$window=[Windows.Window]::new()
$window.Title='AI 記憶黑洞'
$window.Width=$size; $window.Height=$size
$window.WindowStyle='None'; $window.ResizeMode='NoResize'
$window.AllowsTransparency=$true
$window.Background=[Windows.Media.Brushes]::Transparent
$window.ShowInTaskbar=$false
$window.Topmost=$true
$window.Content=$canvas
$window.WindowStartupLocation='Manual'
$canvas.ToolTip='拖曳可移動 · 右鍵可休眠'
$menu=[Windows.Controls.ContextMenu]::new()
$sleepItem=[Windows.Controls.MenuItem]::new()
$sleepItem.Header='休眠'
$sleepItem.Add_Click({ Begin-Sleep })
$statusItem=[Windows.Controls.MenuItem]::new()
$statusItem.Header='記憶狀態'
[void]$menu.Items.Add($statusItem)
$pauseItem=[Windows.Controls.MenuItem]::new()
$pauseItem.Header='暫停記憶傳遞（仍會保存）'
$pauseItem.IsCheckable=$true
$pauseItem.Add_Click({ try { Set-MemoryPaused $pauseItem.IsChecked } catch { $pauseItem.IsChecked=Get-MemoryPaused } })
[void]$menu.Items.Add($pauseItem)
[void]$menu.Items.Add([Windows.Controls.Separator]::new())
[void]$menu.Items.Add($sleepItem)
$menu.Add_Opened({
    $pauseItem.IsChecked=Get-MemoryPaused
    $statusItem.Items.Clear()
    foreach($project in $memoryProjects) {
        $line=[Windows.Controls.MenuItem]::new()
        $line.Header=Get-MemoryStatusLine $project
        $line.IsEnabled=$false
        [void]$statusItem.Items.Add($line)
    }
    $problems=@(Get-MemoryProblems)
    $statusItem.Header=if ($problems.Count) { '記憶狀態（有問題）' } else { '記憶狀態' }
    if ($problems.Count) {
        [void]$statusItem.Items.Add([Windows.Controls.Separator]::new())
        foreach($problem in $problems + '把以上問題告訴 Claude Code 或 Codex 來修復') {
            $line=[Windows.Controls.MenuItem]::new()
            $line.Header=$problem
            $line.IsEnabled=$false
            [void]$statusItem.Items.Add($line)
        }
    }
})
$canvas.ContextMenu=$menu
# 不用 DragMove：它會進入系統的移動模式，開拖時有停頓。改由畫面更新事件把桌寵移到游標位置。
$window.Add_MouseLeftButtonDown({
    if ($_.ButtonState -ne 'Pressed') { return }
    $absorb.DragAt=$_.GetPosition($window)
    if ($window.CaptureMouse()) { $absorb.Dragging=$true }
})
$window.Add_MouseLeftButtonUp({ $window.ReleaseMouseCapture() })
$window.Add_LostMouseCapture({ $absorb.Dragging=$false })
$window.Add_PreviewKeyDown({ if ($_.Key -eq 'Escape') { Begin-Sleep } })
$cursor=[Windows.Forms.Cursor]::Position
$window.Left=$cursor.X-$size/2
$window.Top=$cursor.Y-$size/2
$clock=[Diagnostics.Stopwatch]::new()
# 殘影：桌寵離開喚醒位置後，原地的影像淡出並化為粒子，朝桌寵目前的位置被吸走。只播一次，動畫結束即關閉覆蓋層。
$absorb=@{State='waiting';OriginX=0.0;OriginY=0.0;Left=0.0;Top=0.0;Overlay=$null;Ghost=$null;Items=$null;Clock=$null;Moved=$false;LastFrame=-1000.0;Armed=$false;Dragging=$false;DragAt=$null;IconSize=48.0;Scale=$null;Sleep=$false;SleepT=0.0;SleepFromX=0.0;SleepFromY=0.0;SleepFromScale=1.0;WakeT=0.0;ShortcutFlags=$null}
try {
    $iconSetting=(Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\Shell\Bags\1\Desktop' -ErrorAction Stop).IconSize
    if ($iconSetting -ge 16 -and $iconSetting -le 256) { $absorb.IconSize=[double]$iconSetting }
} catch {}
function Stop-Absorb {
    $absorb.State='done'
    if ($absorb.Overlay) { $absorb.Overlay.Close(); $absorb.Overlay=$null }
}
# 實測第一次畫出全螢幕透明視窗要約 360 毫秒，之後每幀很快。所以在桌寵出現前就顯示好，拖動時不再付這個成本。
# 透明像素不擋滑鼠。桌寵後顯示，所以會在它上面。粒子飛完就關閉。
function Prepare-Absorb {
    $layer=[Windows.Controls.Canvas]::new()
    $layer.IsHitTestVisible=$false
    $ghost=[Windows.Controls.Image]::new()
    $ghost.Width=$absorb.IconSize; $ghost.Height=$absorb.IconSize; $ghost.Opacity=0
    [void]$layer.Children.Add($ghost)
    $items=New-Object 'System.Collections.Generic.List[object]'
    for($i=0;$i -lt 70;$i++) {
        $angle=$random.NextDouble()*6.283185
        $reach=[Math]::Sqrt($random.NextDouble())*$absorb.IconSize/2
        $dotSize=1.2+$random.NextDouble()*2
        $color=@('#FFD291','#FFAE67','#F4804A','#C9683F','#6E4A5C')[$random.Next(5)]
        $shape=Ellipse $layer 0 0 $dotSize $dotSize $color $null 0
        $shape.Opacity=0
        $items.Add(@{Shape=$shape;OffsetX=[Math]::Cos($angle)*$reach;OffsetY=[Math]::Sin($angle)*$reach*.55;X=0.0;Y=0.0;Size=$dotSize;Delay=$random.NextDouble()*.45;Span=.65+$random.NextDouble()*.35;Swirl=1.6+$random.NextDouble();Done=$false})
    }
    $overlay=[Windows.Window]::new()
    $overlay.WindowStyle='None'; $overlay.ResizeMode='NoResize'
    $overlay.AllowsTransparency=$true
    $overlay.Background=[Windows.Media.Brushes]::Transparent
    $overlay.ShowInTaskbar=$false; $overlay.ShowActivated=$false; $overlay.Topmost=$true
    $overlay.WindowStartupLocation='Manual'
    $absorb.Left=[Windows.SystemParameters]::VirtualScreenLeft
    $absorb.Top=[Windows.SystemParameters]::VirtualScreenTop
    $overlay.Left=$absorb.Left; $overlay.Top=$absorb.Top
    $overlay.Width=[Windows.SystemParameters]::VirtualScreenWidth
    $overlay.Height=[Windows.SystemParameters]::VirtualScreenHeight
    $overlay.Content=$layer
    $overlay.Show()
    $absorb.Overlay=$overlay; $absorb.Ghost=$ghost; $absorb.Items=$items
}
function Update-Absorb {
    $now=$absorb.Clock.Elapsed.TotalSeconds
    $targetX=$window.Left+$size/2-$absorb.Left
    $targetY=$window.Top+$size/2-$absorb.Top
    $absorb.Ghost.Opacity=[Math]::Max(0.0,.85*(1-$now/.5))
    $alive=0
    foreach($item in $absorb.Items) {
        if ($item.Done) { continue }
        $progress=($now-$item.Delay)/$item.Span
        if ($progress -ge 1) { $item.Shape.Opacity=0; $item.Done=$true; continue }
        $alive++
        if ($progress -le 0) { $item.Shape.Opacity=[Math]::Min(1.0,$now/.1)*.9; continue }
        $eased=[Math]::Pow($progress,2.4)
        $remain=1-$eased
        $turn=$item.Swirl*$eased
        $cos=[Math]::Cos($turn); $sin=[Math]::Sin($turn)
        $dx=$item.X-$targetX; $dy=$item.Y-$targetY
        $dot=$item.Size*(.35+.65*$remain)
        $item.Shape.Width=$dot; $item.Shape.Height=$dot
        $item.Shape.Opacity=[Math]::Min(1.0,$remain*3)*.95
        [Windows.Controls.Canvas]::SetLeft($item.Shape,$targetX+($dx*$cos-$dy*$sin)*$remain)
        [Windows.Controls.Canvas]::SetTop($item.Shape,$targetY+($dx*$sin+$dy*$cos)*$remain)
    }
    if ($alive -eq 0) { Stop-Absorb }
}
# 喚醒動畫結束後先備好殘影影像和粒子位置，開拖時只需要顯示。
function Arm-Absorb {
    $absorb.Armed=$true
    $snapshot=[Windows.Media.Imaging.RenderTargetBitmap]::new(144,144,96,96,[Windows.Media.PixelFormats]::Pbgra32)
    $snapshot.Render($canvas)
    $originX=$absorb.OriginX-$absorb.Left
    $originY=$absorb.OriginY-$absorb.Top
    $absorb.Ghost.Source=$snapshot
    [Windows.Controls.Canvas]::SetLeft($absorb.Ghost,$originX-$absorb.IconSize/2)
    [Windows.Controls.Canvas]::SetTop($absorb.Ghost,$originY-$absorb.IconSize/2)
    foreach($item in $absorb.Items) {
        $item.X=$originX+$item.OffsetX
        $item.Y=$originY+$item.OffsetY
        [Windows.Controls.Canvas]::SetLeft($item.Shape,$item.X)
        [Windows.Controls.Canvas]::SetTop($item.Shape,$item.Y)
    }
}
function Start-Absorb {
    $absorb.State='running'
    try {
        if (-not $absorb.Armed) { Arm-Absorb }
        $absorb.Ghost.Opacity=.85
        $absorb.Clock=[Diagnostics.Stopwatch]::StartNew()
    } catch { Stop-Absorb }
}
# 動畫跟著畫面更新事件走。實測 DispatcherTimer 受 Windows 計時器精度限制，設 33 毫秒實際約 47 毫秒，只有約 21 幀。
$onFrame=[EventHandler]{
    $frameNow=$clock.Elapsed.TotalMilliseconds
    if ($frameNow-$absorb.LastFrame -lt 12) { return }
    # 每幀最多前進 33 毫秒：畫面停頓時動畫放慢，不會被真實時間直接跳過。
    # 注意：Math.Min/Max 的整數字面值要寫成 1.0，否則 PowerShell 會選整數版本，把小數四捨五入。
    $frameStep=[Math]::Min(33.0,$frameNow-$absorb.LastFrame)
    $absorb.LastFrame=$frameNow
    if ($absorb.Sleep) {
        $absorb.SleepT=[Math]::Min(1.0,$absorb.SleepT+$frameStep/650)
        $sleepEase=$absorb.SleepT*$absorb.SleepT*(3-2*$absorb.SleepT)
        $window.Left=$absorb.SleepFromX+($absorb.OriginX-$size/2-$absorb.SleepFromX)*$sleepEase
        $window.Top=$absorb.SleepFromY+($absorb.OriginY-$size/2-$absorb.SleepFromY)*$sleepEase
        if ($absorb.Scale) {
            $sleepScale=$absorb.SleepFromScale+($absorb.IconSize/144-$absorb.SleepFromScale)*$sleepEase
            $absorb.Scale.ScaleX=$sleepScale; $absorb.Scale.ScaleY=$sleepScale
        }
        Render-Disk ($clock.Elapsed.TotalSeconds*.28)
        if ($absorb.SleepT -ge 1) { Finish-Sleep }
        return
    }
    if ($absorb.WakeT -lt 1) {
        $absorb.WakeT=[Math]::Min(1.0,$absorb.WakeT+$frameStep/700)
        $wakeEase=1-[Math]::Pow(1-$absorb.WakeT,3)
        $wakeScale=$absorb.IconSize/144+(1-$absorb.IconSize/144)*$wakeEase
        $absorb.Scale.ScaleX=$wakeScale; $absorb.Scale.ScaleY=$wakeScale
    }
    if ($transfer.State -eq 'in' -and $transfer.Vortex) {
        $transfer.VortexT=[Math]::Min(1.0,$transfer.VortexT+$frameStep/1150)
        $vortexBitmap=$transfer.VortexBitmap
        $vortexBitmap.Lock()
        $transfer.Vortex.Draw($transfer.VortexT,$vortexBitmap.BackBuffer)
        $vortexBitmap.AddDirtyRect([Windows.Int32Rect]::new(0,0,$vortexBitmap.PixelWidth,$vortexBitmap.PixelHeight))
        $vortexBitmap.Unlock()
        if ($transfer.VortexT -ge 1) {
            $transfer.Vortex=$null
            $transfer.VortexImage.Source=$null
            Start-TransferWait
        }
    }
    if ($absorb.Dragging) {
        $pointer=[Windows.Input.Mouse]::GetPosition($window)
        $moveX=$pointer.X-$absorb.DragAt.X; $moveY=$pointer.Y-$absorb.DragAt.Y
        if ($moveX -ne 0) { $window.Left+=$moveX }
        if ($moveY -ne 0) { $window.Top+=$moveY }
    }
    if (-not $absorb.Armed -and $absorb.State -eq 'waiting' -and $absorb.WakeT -ge 1) { try { Arm-Absorb } catch { $absorb.State='done' } }
    Render-Disk ($clock.Elapsed.TotalSeconds*.28)
    if ($absorb.State -eq 'running') {
        try { Update-Absorb } catch { Stop-Absorb }
    }
    if ($absorb.State -eq 'waiting') {
        $awayX=$window.Left+$size/2-$absorb.OriginX
        $awayY=$window.Top+$size/2-$absorb.OriginY
        if ([Math]::Sqrt($awayX*$awayX+$awayY*$awayY) -gt 56) { Start-Absorb }
    }
    if ($SmokeTest) {
        if (-not $absorb.Moved -and $clock.Elapsed.TotalMilliseconds -gt 280) {
            $absorb.Moved=$true
            $window.Left+=if ($window.Left -gt [Windows.SystemParameters]::WorkArea.Width/2) { -320 } else { 320 }
        }
        if ($absorb.State -eq 'done' -or $clock.Elapsed.TotalMilliseconds -gt 6000) { $window.Close() }
    }
}
# 全螢幕程式（遊戲、影片）在最前面時隱藏桌寵並暫停動畫，避免蓋住畫面。離開全螢幕約 2 秒後恢復。
$fullscreen=@{Enabled=$true;Hidden=$false;ClearChecks=0;Timer=$null}
try {
    Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices; using System.Text;
namespace BlackHolePet {
  public static class Foreground {
    [StructLayout(LayoutKind.Sequential)] struct RECT { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] struct MONITORINFO { public int cbSize; public RECT rcMonitor; public RECT rcWork; public int dwFlags; }
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] static extern int GetWindowLong(IntPtr h, int i);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] static extern IntPtr MonitorFromWindow(IntPtr h, uint f);
    [DllImport("user32.dll")] static extern bool GetMonitorInfo(IntPtr m, ref MONITORINFO i);
    const int GWL_STYLE = -16; const int WS_CAPTION = 0x00C00000;
    public static bool IsFullscreen(int ownPid) {
      IntPtr h = GetForegroundWindow();
      if (h == IntPtr.Zero) return false;
      uint pid; GetWindowThreadProcessId(h, out pid);
      if (pid == (uint)ownPid) return false;
      var c = new StringBuilder(64); GetClassName(h, c, 64);
      string k = c.ToString();
      if (k == "Progman" || k == "WorkerW" || k == "Shell_TrayWnd") return false;
      if ((GetWindowLong(h, GWL_STYLE) & WS_CAPTION) == WS_CAPTION) return false;
      RECT r; if (!GetWindowRect(h, out r)) return false;
      var m = new MONITORINFO(); m.cbSize = Marshal.SizeOf(typeof(MONITORINFO));
      if (!GetMonitorInfo(MonitorFromWindow(h, 2), ref m)) return false;
      return r.Left <= m.rcMonitor.Left && r.Top <= m.rcMonitor.Top && r.Right >= m.rcMonitor.Right && r.Bottom >= m.rcMonitor.Bottom;
    }
  }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
  [ComImport, Guid("85CB6900-4D95-11CF-960C-0080C7F4EE85"), InterfaceType(ComInterfaceType.InterfaceIsDual)]
  interface IShellWindows {
    void Reserved1(); void Reserved2(); void Reserved3(); void Reserved4(); void Reserved5(); void Reserved6(); void Reserved7(); void Reserved8();
    [return: MarshalAs(UnmanagedType.IDispatch)] object FindWindowSW([MarshalAs(UnmanagedType.Struct)] ref object loc, [MarshalAs(UnmanagedType.Struct)] ref object root, int cls, out int hwnd, int options);
  }
  [ComImport, Guid("6D5140C1-7436-11CE-8034-00AA006009FA"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IServiceProvider2 { [PreserveSig] int QueryService(ref Guid sid, ref Guid iid, [MarshalAs(UnmanagedType.IUnknown)] out object o); }
  [ComImport, Guid("000214E2-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IShellBrowser {
    void GetWindow(out IntPtr h); void ContextSensitiveHelp(int f); void InsertMenusSB(IntPtr a, IntPtr b); void SetMenuSB(IntPtr a, IntPtr b, IntPtr c);
    void RemoveMenusSB(IntPtr a); void SetStatusTextSB(IntPtr a); void EnableModelessSB(int f); void TranslateAcceleratorSB(IntPtr a, short b);
    void BrowseObject(IntPtr a, uint b); void GetViewStateStream(uint a, out IntPtr b); void GetControlWindow(uint a, out IntPtr b); void SendControlMsg(uint a, uint b, IntPtr c, IntPtr d, IntPtr e);
    void QueryActiveShellView([MarshalAs(UnmanagedType.IUnknown)] out object view);
  }
  [ComImport, Guid("CDE725B0-CCC9-4519-917E-325D72FAB4CE"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IFolderView {
    void GetCurrentViewMode(out uint m); void SetCurrentViewMode(uint m); void GetFolder(ref Guid iid, out IntPtr p);
    void Item(int i, out IntPtr pidl); void ItemCount(uint flags, out int n); void Items(uint f, ref Guid iid, out IntPtr p);
    void GetSelectionMarkedItem(out int i); void GetFocusedItem(out int i); void GetItemPosition(IntPtr pidl, out POINT pt);
    void GetSpacing(ref POINT pt);
  }
  public class IconSpot { public int X, Y, CellX, CellY; }
  // 向桌面的外殼介面查詢圖示位置（實體像素）。不讀取 explorer 的記憶體。
  public static class DesktopIcon {
    [DllImport("shell32.dll", CharSet=CharSet.Unicode)] static extern int SHGetNameFromIDList(IntPtr pidl, uint sigdn, out IntPtr name);
    static string NameOf(IntPtr pidl) { IntPtr s; if (SHGetNameFromIDList(pidl, 0, out s) != 0) return ""; string r = Marshal.PtrToStringUni(s); Marshal.FreeCoTaskMem(s); return r; }
    public static IconSpot Find(string name) {
      var t = Type.GetTypeFromCLSID(new Guid("9BA05972-F6A8-11CF-A442-00A0C90A8F39"));
      var sw = (IShellWindows)Activator.CreateInstance(t);
      object loc = 0, root = Type.Missing; int hwnd;
      var sp = (IServiceProvider2)sw.FindWindowSW(ref loc, ref root, 8, out hwnd, 1);
      Guid sid = new Guid("4C96BE40-915C-11CF-99D3-00AA004AE837"), iid = typeof(IShellBrowser).GUID; object b;
      Marshal.ThrowExceptionForHR(sp.QueryService(ref sid, ref iid, out b));
      object v; ((IShellBrowser)b).QueryActiveShellView(out v);
      var view = (IFolderView)v; int n; view.ItemCount(2, out n);
      for (int i = 0; i < n; i++) {
        IntPtr p; view.Item(i, out p);
        try {
          string s = NameOf(p);
          if (s == name || s == name + ".lnk") {
            POINT pt; view.GetItemPosition(p, out pt); var cell = new POINT(); view.GetSpacing(ref cell);
            return new IconSpot { X = pt.X, Y = pt.Y, CellX = cell.X, CellY = cell.Y };
          }
        } finally { Marshal.FreeCoTaskMem(p); }
      }
      return null;
    }
  }
  // 漩渦吸入：把截圖切成網格，離黑洞最近的角先被吸走，其餘部分依距離延後，沿螺旋被拉進黑洞。純軟體繪製。
  public class Vortex {
    readonly int sw, sh, dw, dh, cols, rows; readonly int[] src, dst, order;
    readonly double hx, hy; readonly double[] bx, by, delay, vx, vy, va;
    public Vortex(byte[] png, int dstW, int dstH, double winX, double winY, double winW, double winH, double holeX, double holeY) {
      dw = dstW; dh = dstH; hx = holeX; hy = holeY; dst = new int[dw * dh];
      sw = Math.Max(1, (int)winW); sh = Math.Max(1, (int)winH); src = new int[sw * sh];
      using (var ms = new System.IO.MemoryStream(png)) using (var from = new System.Drawing.Bitmap(ms))
      using (var small = new System.Drawing.Bitmap(sw, sh, System.Drawing.Imaging.PixelFormat.Format32bppArgb))
      using (var g = System.Drawing.Graphics.FromImage(small)) {
        g.DrawImage(from, 0, 0, sw, sh);
        var lk = small.LockBits(new System.Drawing.Rectangle(0, 0, sw, sh), System.Drawing.Imaging.ImageLockMode.ReadOnly, small.PixelFormat);
        for (int y = 0; y < sh; y++) Marshal.Copy(IntPtr.Add(lk.Scan0, y * lk.Stride), src, y * sw, sw);
        small.UnlockBits(lk);
      }
      cols = 72; rows = Math.Max(16, Math.Min(72, (int)(72 * winH / Math.Max(1, winW))));
      int n = (cols + 1) * (rows + 1);
      bx = new double[n]; by = new double[n]; delay = new double[n]; vx = new double[n]; vy = new double[n]; va = new double[n];
      double ax = Math.Abs(winX - hx) < Math.Abs(winX + winW - hx) ? winX : winX + winW;
      double ay = Math.Abs(winY - hy) < Math.Abs(winY + winH - hy) ? winY : winY + winH;
      double far = 1;
      for (int r = 0; r <= rows; r++) for (int c = 0; c <= cols; c++) {
        int i = r * (cols + 1) + c;
        bx[i] = winX + winW * c / cols; by[i] = winY + winH * r / rows;
        double dist = Math.Sqrt((bx[i] - ax) * (bx[i] - ax) + (by[i] - ay) * (by[i] - ay));
        delay[i] = dist; if (dist > far) far = dist;
      }
      for (int i = 0; i < n; i++) delay[i] /= far;
      order = new int[cols * rows]; var keys = new double[order.Length];
      for (int r = 0; r < rows; r++) for (int c = 0; c < cols; c++) { int k = r * cols + c; order[k] = k; keys[k] = -delay[r * (cols + 1) + c]; }
      Array.Sort(keys, order);
    }
    public void Draw(double t, IntPtr back) {
      Array.Clear(dst, 0, dst.Length);
      for (int i = 0; i < bx.Length; i++) {
        double p = (t - delay[i] * 0.55) / 0.45; if (p < 0) p = 0; else if (p > 1) p = 1;
        // 先往黑洞收縮，接近時才加速旋轉，避免畫面甩出大弧、超出繪製範圍。
        double e = p * p, r = 1 - e, turn = e * e * e * (2.4 + delay[i] * 1.2), co = Math.Cos(turn), si = Math.Sin(turn);
        double dx = bx[i] - hx, dy = by[i] - hy;
        vx[i] = hx + (dx * co - dy * si) * r; vy[i] = hy + (dx * si + dy * co) * r;
        va[i] = r * 5 > 1 ? 1 : r * 5;
      }
      foreach (int k in order) {
        int r = k / cols, c = k % cols, a = r * (cols + 1) + c, b = a + 1, d = a + cols + 1, f = d + 1;
        if (va[a] <= 0 && va[b] <= 0 && va[d] <= 0 && va[f] <= 0) continue;
        double u0 = (double)c / cols, u1 = (double)(c + 1) / cols, v0 = (double)r / rows, v1 = (double)(r + 1) / rows;
        Tri(a, b, f, u0, v0, u1, v0, u1, v1); Tri(a, f, d, u0, v0, u1, v1, u0, v1);
      }
      Marshal.Copy(dst, 0, back, dst.Length);
    }
    void Tri(int i0, int i1, int i2, double u0, double v0, double u1, double v1, double u2, double v2) {
      double x0 = vx[i0], y0 = vy[i0], x1 = vx[i1], y1 = vy[i1], x2 = vx[i2], y2 = vy[i2];
      double area = (x1 - x0) * (y2 - y0) - (x2 - x0) * (y1 - y0);
      if (Math.Abs(area) < 0.05) return;
      int minX = Math.Max(0, (int)Math.Floor(Math.Min(x0, Math.Min(x1, x2)))), maxX = Math.Min(dw - 1, (int)Math.Ceiling(Math.Max(x0, Math.Max(x1, x2))));
      int minY = Math.Max(0, (int)Math.Floor(Math.Min(y0, Math.Min(y1, y2)))), maxY = Math.Min(dh - 1, (int)Math.Ceiling(Math.Max(y0, Math.Max(y1, y2))));
      double alpha = (va[i0] + va[i1] + va[i2]) / 3; int al = (int)(alpha * 256); if (al <= 0) return;
      double inv = 1 / area;
      for (int y = minY; y <= maxY; y++) {
        double py = y + 0.5; int row = y * dw;
        for (int x = minX; x <= maxX; x++) {
          double px = x + 0.5;
          double w1 = ((px - x0) * (y2 - y0) - (x2 - x0) * (py - y0)) * inv;
          double w2 = ((x1 - x0) * (py - y0) - (px - x0) * (y1 - y0)) * inv;
          double w0 = 1 - w1 - w2;
          if (w0 < -0.02 || w1 < -0.02 || w2 < -0.02) continue;
          int su = (int)((w0 * u0 + w1 * u1 + w2 * u2) * sw), sv = (int)((w0 * v0 + w1 * v1 + w2 * v2) * sh);
          if (su < 0) su = 0; else if (su >= sw) su = sw - 1; if (sv < 0) sv = 0; else if (sv >= sh) sv = sh - 1;
          int s = src[sv * sw + su] | unchecked((int)0xFF000000);
          if (al >= 256) dst[row + x] = s;
          else {
            uint u = (uint)s; uint rb = ((u & 0xFF00FF) * (uint)al >> 8) & 0xFF00FF, g = ((u & 0x00FF00) * (uint)al >> 8) & 0x00FF00;
            dst[row + x] = (int)(((uint)al - 1 & 0xFF) << 24 | rb | g);
          }
        }
      }
    }
  }
  // 吸入動畫原型用：找到剛啟動程式的主視窗、截圖、暫時移開再放回。只呼叫一般視窗 API，不注入對方程序。
  public static class WindowTool {
    struct RECT { public int Left, Top, Right, Bottom; }
    delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc p, IntPtr l);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] static extern IntPtr GetWindow(IntPtr h, uint c);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int w, int ht, uint f);
    [DllImport("user32.dll")] static extern bool PrintWindow(IntPtr h, IntPtr dc, uint f);
    const uint MOVE_ONLY = 0x0001 | 0x0004 | 0x0010; // NOSIZE | NOZORDER | NOACTIVATE
    public static IntPtr FindFresh(string name, double maxAgeSeconds) {
      var pids = new System.Collections.Generic.HashSet<uint>();
      foreach (var p in System.Diagnostics.Process.GetProcessesByName(name)) {
        try { if ((DateTime.Now - p.StartTime).TotalSeconds <= maxAgeSeconds) pids.Add((uint)p.Id); } catch { } finally { p.Dispose(); }
      }
      if (pids.Count == 0) return IntPtr.Zero;
      IntPtr found = IntPtr.Zero;
      EnumWindows((h, l) => {
        if (!IsWindowVisible(h) || GetWindow(h, 4) != IntPtr.Zero) return true;
        uint pid; GetWindowThreadProcessId(h, out pid);
        if (!pids.Contains(pid)) return true;
        RECT r; if (!GetWindowRect(h, out r) || r.Right - r.Left < 400 || r.Bottom - r.Top < 300) return true;
        found = h; return false;
      }, IntPtr.Zero);
      return found;
    }
    public static int[] GetRect(IntPtr h) { RECT r; GetWindowRect(h, out r); return new[] { r.Left, r.Top, r.Right - r.Left, r.Bottom - r.Top }; }
    public static void MoveTo(IntPtr h, int x, int y) { SetWindowPos(h, IntPtr.Zero, x, y, 0, 0, MOVE_ONLY); }
    static System.Drawing.Bitmap Grab(IntPtr h) {
      RECT r; GetWindowRect(h, out r);
      var b = new System.Drawing.Bitmap(Math.Max(1, r.Right - r.Left), Math.Max(1, r.Bottom - r.Top));
      using (var g = System.Drawing.Graphics.FromImage(b)) { IntPtr dc = g.GetHdc(); PrintWindow(h, dc, 2); g.ReleaseHdc(dc); }
      return b;
    }
    public static byte[] CapturePng(IntPtr h) {
      using (var b = Grab(h)) using (var s = new System.IO.MemoryStream()) { b.Save(s, System.Drawing.Imaging.ImageFormat.Png); return s.ToArray(); }
    }
    public static long CaptureHash(IntPtr h) {
      using (var b = Grab(h)) {
        long hash = 17;
        for (int y = 0; y < 27; y++) for (int x = 0; x < 48; x++) {
          var c = b.GetPixel(x * (b.Width - 1) / 47, y * (b.Height - 1) / 26);
          hash = hash * 31 + (c.R >> 3) + (c.G >> 3) * 37 + (c.B >> 3) * 1009;
        }
        return hash;
      }
    }
  }
}
'@ -ReferencedAssemblies System.Drawing
} catch { $fullscreen.Enabled=$false }
# 休眠：飛回喚醒位置並縮回圖示大小，再恢復桌面圖示。外層啟動程序仍會在退出時再確認一次。
function Begin-Sleep {
    if ($absorb.Sleep) { return }
    $window.ReleaseMouseCapture()
    if ($absorb.State -eq 'running') { Stop-Absorb }
    $absorb.SleepFromX=$window.Left; $absorb.SleepFromY=$window.Top
    if ($absorb.Scale) { $absorb.SleepFromScale=$absorb.Scale.ScaleX }
    $absorb.SleepT=0
    $absorb.Sleep=$true
}
function Finish-Sleep {
    if ($absorb.ShortcutFlags -ne $null -and [IO.File]::Exists($shortcut)) { [IO.File]::SetAttributes($shortcut,$absorb.ShortcutFlags) }
    $window.Close()
}
# 記憶連動：讀取三個項目的記憶橋接狀態和暫停設定。記憶本身不依賴桌寵，桌寵關閉時照常運作。
$memoryProjects=@(try { (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'projects.json') -Raw -Encoding UTF8 | ConvertFrom-Json) | ForEach-Object { ,@($_.name,$_.path) } } catch { @() })
function Get-MemoryPaused { Test-Path -LiteralPath (Join-Path $memoryProjects[0][1] '.memory-bridge\paused') }
function Set-MemoryPaused([bool]$paused) {
    foreach($project in $memoryProjects) {
        $flag=Join-Path $project[1] '.memory-bridge\paused'
        if ($paused) { if (-not (Test-Path -LiteralPath $flag)) { [IO.File]::WriteAllText($flag,'') } }
        elseif (Test-Path -LiteralPath $flag) { Remove-Item -LiteralPath $flag -Force -Confirm:$false }
    }
    $canvas.Opacity=if ($paused) { .72 } else { 1 }
}
function Get-MemoryStatusLine($project) {
    try {
        $info=[Diagnostics.ProcessStartInfo]::new('node','.memory-bridge/bridge.js status')
        $info.WorkingDirectory=$project[1]; $info.UseShellExecute=$false; $info.CreateNoWindow=$true; $info.RedirectStandardOutput=$true
        $process=[Diagnostics.Process]::Start($info)
        $text=$process.StandardOutput.ReadToEnd(); [void]$process.WaitForExit(2000)
        $parts=foreach($tool in @(@('claude','Claude Code','codex'),@('codex','Codex','claude'))) {
            $match=[regex]::Match($text,"(?m)^$($tool[0]): (\d+) records.*delivered_to_$($tool[2])=(true|false)")
            if ($match.Success) { "$($tool[1]) $($match.Groups[1].Value) 筆" + $(if ($match.Groups[2].Value -eq 'false') { '（待對方讀取）' } else { '' }) }
        }
        if ($parts) { "$($project[0])：$($parts -join '，')" } else { "$($project[0])：還沒有記錄" }
    } catch { "$($project[0])：無法讀取" }
}
function Get-LatestMemoryWrite {
    $latest=[datetime]::MinValue
    foreach($project in $memoryProjects) {
        $dir=Join-Path $project[1] '.memory-bridge\log'
        if ([IO.Directory]::Exists($dir)) {
            foreach($file in [IO.Directory]::GetFiles($dir,'*.jsonl')) {
                $time=[IO.File]::GetLastWriteTimeUtc($file)
                if ($time -gt $latest) { $latest=$time }
            }
        }
    }
    $latest
}
function Show-MemoryPulse {
    $fade=[Windows.Media.Animation.DoubleAnimation]::new(.95,0,[Windows.Duration]::new([TimeSpan]::FromMilliseconds(1200)))
    $grow=[Windows.Media.Animation.DoubleAnimation]::new(1,1.9,[Windows.Duration]::new([TimeSpan]::FromMilliseconds(1200)))
    $memoryPulse.BeginAnimation([Windows.Shapes.Shape]::OpacityProperty,$fade)
    $memoryPulseScale.BeginAnimation([Windows.Media.ScaleTransform]::ScaleXProperty,$grow)
    $memoryPulseScale.BeginAnimation([Windows.Media.ScaleTransform]::ScaleYProperty,$grow)
}
$memoryPulse=Ellipse $canvas 40 40 64 64 $null '#FFFFB070' 2
$memoryPulse.Opacity=0
$memoryPulseScale=[Windows.Media.ScaleTransform]::new(1,1,32,32)
$memoryPulse.RenderTransform=$memoryPulseScale
# 斷線警告：Hook 失敗時對話不受影響，使用者不會發現。背景輪流檢查三個項目，有問題時紅圈閃爍，右鍵的「記憶狀態」列出原因。
# 用非同步程序，不等待結果，避免畫面停頓；全螢幕時不啟動新檢查。
$memoryAlarm=Ellipse $canvas 40 40 64 64 $null '#FFFF3B30' 3
$memoryAlarm.Opacity=0
$memoryHealth=@{Index=0;Process=$null;StartedAt=[datetime]::MinValue;NextAt=[datetime]::UtcNow.AddSeconds(5);Problems=@{};Alarm=$false}
function Get-MemoryProblems {
    foreach($project in $memoryProjects) {
        foreach($problem in @($memoryHealth.Problems[$project[0]])) {
            if ($problem) { "$($project[0])：$problem" }
        }
    }
}
function Show-MemoryAlarm {
    $active=@(Get-MemoryProblems).Count -gt 0
    if ($active -eq $memoryHealth.Alarm) { return }
    $memoryHealth.Alarm=$active
    if ($active) {
        $blink=[Windows.Media.Animation.DoubleAnimation]::new(.35,1,[Windows.Duration]::new([TimeSpan]::FromMilliseconds(900)))
        $blink.AutoReverse=$true
        $blink.RepeatBehavior=[Windows.Media.Animation.RepeatBehavior]::Forever
        $memoryAlarm.BeginAnimation([Windows.Shapes.Shape]::OpacityProperty,$blink)
    } else {
        $memoryAlarm.BeginAnimation([Windows.Shapes.Shape]::OpacityProperty,$null)
        $memoryAlarm.Opacity=0
    }
}
function Complete-MemoryHealth($problems) {
    $memoryHealth.Problems[$memoryProjects[$memoryHealth.Index][0]]=@($problems)
    $memoryHealth.Process=$null
    $memoryHealth.Index++
    if ($memoryHealth.Index -ge $memoryProjects.Count) {
        $memoryHealth.Index=0
        $memoryHealth.NextAt=[datetime]::UtcNow.AddSeconds(60)
    }
    Show-MemoryAlarm
}
function Update-MemoryHealth {
    $process=$memoryHealth.Process
    if ($process) {
        if (-not $process.HasExited) {
            if (([datetime]::UtcNow-$memoryHealth.StartedAt).TotalSeconds -gt 15) {
                try { $process.Kill() } catch {}
                Complete-MemoryHealth '記憶程式沒有回應'
            }
            return
        }
        $problems='記憶程式無法執行'
        try {
            $text=$process.StandardOutput.ReadToEnd()
            if ($process.ExitCode -eq 0) { $problems=@(($text | ConvertFrom-Json).problems) }
        } catch {}
        Complete-MemoryHealth $problems
        return
    }
    if ([datetime]::UtcNow -lt $memoryHealth.NextAt -or $fullscreen.Hidden -or $absorb.Sleep) { return }
    try {
        $info=[Diagnostics.ProcessStartInfo]::new('node','.memory-bridge/bridge.js health')
        $info.WorkingDirectory=$memoryProjects[$memoryHealth.Index][1]; $info.UseShellExecute=$false; $info.CreateNoWindow=$true; $info.RedirectStandardOutput=$true
        $memoryHealth.StartedAt=[datetime]::UtcNow
        $memoryHealth.Process=[Diagnostics.Process]::Start($info)
    } catch { Complete-MemoryHealth '無法啟動 node 或找不到項目資料夾' }
}
$memoryWatch=@{Latest=(Get-LatestMemoryWrite)}
$memoryTimer=[Windows.Threading.DispatcherTimer]::new()
$memoryTimer.Interval=[TimeSpan]::FromSeconds(2)
$memoryTimer.Add_Tick({
    try {
        $latest=Get-LatestMemoryWrite
        if ($latest -gt $memoryWatch.Latest) {
            $memoryWatch.Latest=$latest
            if (-not $fullscreen.Hidden -and -not $absorb.Sleep) { Show-MemoryPulse }
        }
    } catch { $memoryTimer.Stop() }
    try { Update-MemoryHealth } catch {}
})
$memoryTimer.Start()
if (Get-MemoryPaused) { $canvas.Opacity=.72 }
# 吸入動畫：打開 Codex（程序名 ChatGPT）或 Claude 時播放。視窗吐出前使用者無法傳訊息，
# 而記憶是在第一則訊息時由 Hook 附上，所以記憶自然在動畫結束後才交接，不需要額外的暫停旗標。
# 新視窗出現時先截圖蓋住真視窗，把真視窗暫時移到螢幕外讓它繼續載入，截圖吸入黑洞；畫面穩定或逾時後吐出並放回。
if (-not $TransferTarget -and -not $SmokeTest) { $TransferTarget='ChatGPT,Claude' }
$transfer=@{State='idle';StartedAt=$null;Hwnd=[IntPtr]::Zero;Rect=$null;Moved=$false;Window=$null;Image=$null;Scale=$null;Turn=$null;Shift=$null;Handled=@{};OnDone=$null;Wait=$null;Clock=$null;Hash=0L;Stable=0;Changed=$false;Ticks=0;Timer=$null;Vortex=$null;VortexT=0.0;VortexBitmap=$null;VortexImage=$null;Png=$null}
function New-BitmapFromPng([byte[]]$png) {
    $bitmap=[Windows.Media.Imaging.BitmapImage]::new()
    $bitmap.BeginInit(); $bitmap.CacheOption='OnLoad'; $bitmap.StreamSource=[IO.MemoryStream]::new($png); $bitmap.EndInit(); $bitmap.Freeze()
    $bitmap
}
function Restore-TransferWindow {
    if ($transfer.Moved) { [BlackHolePet.WindowTool]::MoveTo($transfer.Hwnd,$transfer.Rect[0],$transfer.Rect[1]); $transfer.Moved=$false }
}
function End-Transfer {
    Restore-TransferWindow
    $transfer.Vortex=$null
    if ($transfer.Wait) { $transfer.Wait.Stop(); $transfer.Wait=$null }
    if ($transfer.Window) { $transfer.Window.Close(); $transfer.Window=$null }
    $transfer.State='idle'
}
function Invoke-TransferMotion([double]$fromScale,[double]$toScale,[double]$fromTurn,[double]$toTurn,[double]$fromX,[double]$toX,[double]$fromY,[double]$toY,[string]$easing,[int]$ms,[scriptblock]$onDone) {
    $duration=[Windows.Duration]::new([TimeSpan]::FromMilliseconds($ms))
    $ease=[Windows.Media.Animation.CubicEase]::new(); $ease.EasingMode=$easing
    $transfer.OnDone=$onDone
    $make={ param($from,$to) $a=[Windows.Media.Animation.DoubleAnimation]::new($from,$to,$duration); $a.EasingFunction=$ease; $a }
    $scaleMotion=& $make $fromScale $toScale
    $scaleMotion.Add_Completed({ try { & $transfer.OnDone } catch { End-Transfer } })
    $transfer.Scale.BeginAnimation([Windows.Media.ScaleTransform]::ScaleXProperty,$scaleMotion)
    $transfer.Scale.BeginAnimation([Windows.Media.ScaleTransform]::ScaleYProperty,(& $make $fromScale $toScale))
    $transfer.Turn.BeginAnimation([Windows.Media.RotateTransform]::AngleProperty,(& $make $fromTurn $toTurn))
    $transfer.Shift.BeginAnimation([Windows.Media.TranslateTransform]::XProperty,(& $make $fromX $toX))
    $transfer.Shift.BeginAnimation([Windows.Media.TranslateTransform]::YProperty,(& $make $fromY $toY))
}
function Get-TransferOffset {
    $source=[Windows.PresentationSource]::FromVisual($window)
    $toDip=$source.CompositionTarget.TransformFromDevice
    $topLeft=$toDip.Transform([Windows.Point]::new($transfer.Rect[0],$transfer.Rect[1]))
    $bottomRight=$toDip.Transform([Windows.Point]::new($transfer.Rect[0]+$transfer.Rect[2],$transfer.Rect[1]+$transfer.Rect[3]))
    @{Left=$topLeft.X;Top=$topLeft.Y;Width=$bottomRight.X-$topLeft.X;Height=$bottomRight.Y-$topLeft.Y;
      ToPetX=$window.Left+$size/2-($topLeft.X+$bottomRight.X)/2;ToPetY=$window.Top+$size/2-($topLeft.Y+$bottomRight.Y)/2}
}
function Start-TransferSpit {
    $transfer.Wait.Stop(); $transfer.Wait=$null
    $transfer.State='out'
    $transfer.Image.Source=New-BitmapFromPng ([BlackHolePet.WindowTool]::CapturePng($transfer.Hwnd))
    $offset=Get-TransferOffset
    Invoke-TransferMotion .02 1 220 0 $offset.ToPetX 0 $offset.ToPetY 0 'EaseOut' 550 { End-Transfer; Show-MemoryPulse }
}
function Start-TransferWait {
    $transfer.State='wait'
    $transfer.Clock=[Diagnostics.Stopwatch]::StartNew()
    $transfer.Hash=[BlackHolePet.WindowTool]::CaptureHash($transfer.Hwnd)
    $transfer.Stable=0; $transfer.Changed=$false; $transfer.Ticks=0
    $transfer.Wait=[Windows.Threading.DispatcherTimer]::new()
    $transfer.Wait.Interval=[TimeSpan]::FromMilliseconds(400)
    $transfer.Wait.Add_Tick({
        try {
            $transfer.Ticks++
            if ($transfer.Ticks % 3 -eq 1) { Show-MemoryPulse }
            $hash=[BlackHolePet.WindowTool]::CaptureHash($transfer.Hwnd)
            if ($hash -eq $transfer.Hash) { $transfer.Stable++ } else { $transfer.Stable=0; $transfer.Changed=$true; $transfer.Hash=$hash }
            $elapsed=$transfer.Clock.Elapsed.TotalMilliseconds
            # 沒有官方的「載入完成」訊號，所以用畫面穩定來推測。不論如何 8 秒內一定吐出，不能擋住應用程式。
            if ($elapsed -ge 8000 -or ($elapsed -ge 1200 -and $transfer.Stable -ge 3 -and ($transfer.Changed -or $elapsed -ge 4000))) {
                $transfer.Image.Opacity=1
                Start-TransferSpit
            }
        } catch { End-Transfer }
    })
    $transfer.Wait.Start()
}
function Start-Transfer([IntPtr]$hwnd) {
    $transfer.State='in'
    $transfer.StartedAt=[Diagnostics.Stopwatch]::StartNew()
    $transfer.Hwnd=$hwnd
    $transfer.Handled["$hwnd"]=$true
    try {
        $transfer.Rect=[BlackHolePet.WindowTool]::GetRect($hwnd)
        $offset=Get-TransferOffset
        $image=[Windows.Controls.Image]::new()
        $transfer.Png=[BlackHolePet.WindowTool]::CapturePng($hwnd)
        $image.Source=New-BitmapFromPng $transfer.Png
        $image.Width=$offset.Width; $image.Height=$offset.Height; $image.Stretch='Fill'
        $transfer.Scale=[Windows.Media.ScaleTransform]::new(1,1,$offset.Width/2,$offset.Height/2)
        $transfer.Turn=[Windows.Media.RotateTransform]::new(0,$offset.Width/2,$offset.Height/2)
        $transfer.Shift=[Windows.Media.TranslateTransform]::new(0,0)
        $group=[Windows.Media.TransformGroup]::new()
        $group.Children.Add($transfer.Scale); $group.Children.Add($transfer.Turn); $group.Children.Add($transfer.Shift)
        $image.RenderTransform=$group
        $transfer.Image=$image
        $layer=[Windows.Controls.Canvas]::new()
        $layer.IsHitTestVisible=$false
        $screenLeft=[Windows.SystemParameters]::VirtualScreenLeft; $screenTop=[Windows.SystemParameters]::VirtualScreenTop
        [Windows.Controls.Canvas]::SetLeft($image,$offset.Left-$screenLeft)
        [Windows.Controls.Canvas]::SetTop($image,$offset.Top-$screenTop)
        [void]$layer.Children.Add($image)
        $stage=[Windows.Window]::new()
        $stage.WindowStyle='None'; $stage.ResizeMode='NoResize'; $stage.AllowsTransparency=$true
        $stage.Background=[Windows.Media.Brushes]::Transparent
        $stage.ShowInTaskbar=$false; $stage.ShowActivated=$false; $stage.Topmost=$true
        $stage.WindowStartupLocation='Manual'
        $stage.Left=$screenLeft; $stage.Top=$screenTop
        $stage.Width=[Windows.SystemParameters]::VirtualScreenWidth; $stage.Height=[Windows.SystemParameters]::VirtualScreenHeight
        $stage.Content=$layer
        $transfer.Window=$stage
        # 等截圖真的畫出來才移開真視窗，避免中間閃一下空白。
        $stage.Add_ContentRendered({
            try {
                [BlackHolePet.WindowTool]::MoveTo($transfer.Hwnd,-32000,-32000)
                $transfer.Moved=$true
                $window.Topmost=$false; $window.Topmost=$true
                # 繪製範圍只取視窗和黑洞的聯集，用一半解析度，放大顯示。
                $now=Get-TransferOffset
                $petX=$window.Left+$size/2; $petY=$window.Top+$size/2
                # 螺旋會繞過黑洞，所以外圍多留一點，尾巴才不會被切掉。
                $areaLeft=[Math]::Min($now.Left,$petX-220); $areaTop=[Math]::Min($now.Top,$petY-220)
                $areaRight=[Math]::Max($now.Left+$now.Width,$petX+220); $areaBottom=[Math]::Max($now.Top+$now.Height,$petY+220)
                $pixelW=[int][Math]::Ceiling(($areaRight-$areaLeft)*.625); $pixelH=[int][Math]::Ceiling(($areaBottom-$areaTop)*.625)
                $toPixel=$pixelW/($areaRight-$areaLeft)
                $transfer.VortexBitmap=[Windows.Media.Imaging.WriteableBitmap]::new($pixelW,$pixelH,96,96,[Windows.Media.PixelFormats]::Pbgra32,$null)
                $transfer.Vortex=[BlackHolePet.Vortex]::new($transfer.Png,$pixelW,$pixelH,($now.Left-$areaLeft)*$toPixel,($now.Top-$areaTop)*$toPixel,$now.Width*$toPixel,$now.Height*$toPixel,($petX-$areaLeft)*$toPixel,($petY-$areaTop)*$toPixel)
                $transfer.VortexT=0
                $vortexImage=[Windows.Controls.Image]::new()
                $vortexImage.Source=$transfer.VortexBitmap
                $vortexImage.Width=$areaRight-$areaLeft; $vortexImage.Height=$areaBottom-$areaTop; $vortexImage.Stretch='Fill'
                [Windows.Controls.Canvas]::SetLeft($vortexImage,$areaLeft-[Windows.SystemParameters]::VirtualScreenLeft)
                [Windows.Controls.Canvas]::SetTop($vortexImage,$areaTop-[Windows.SystemParameters]::VirtualScreenTop)
                $transfer.VortexImage=$vortexImage
                [void]$transfer.Image.Parent.Children.Add($vortexImage)
                $transfer.Image.Opacity=0
            } catch { End-Transfer }
        })
        $stage.Show()
    } catch { End-Transfer }
}
if ($TransferTarget -and $fullscreen.Enabled) {
    $transfer.Timer=[Windows.Threading.DispatcherTimer]::new()
    $transfer.Timer.Interval=[TimeSpan]::FromMilliseconds(300)
    $transfer.Timer.Add_Tick({
        try {
            # 保險：流程卡住時強制放回真視窗，不讓畫面停在半路。
            if ($transfer.State -ne 'idle') {
                if ($transfer.StartedAt -and $transfer.StartedAt.Elapsed.TotalSeconds -gt 20) { End-Transfer }
                return
            }
            if ($fullscreen.Hidden -or $absorb.Sleep) { return }
            foreach($target in $TransferTarget.Split(',')) {
                $hwnd=[BlackHolePet.WindowTool]::FindFresh($target,20)
                if ($hwnd -ne [IntPtr]::Zero -and -not $transfer.Handled.ContainsKey("$hwnd")) { Start-Transfer $hwnd; break }
            }
        } catch { $transfer.Timer.Stop() }
    })
    $transfer.Timer.Start()
}
function Hide-ForFullscreen {
    if ($absorb.Sleep) { Finish-Sleep; return }
    $fullscreen.Hidden=$true
    $window.ReleaseMouseCapture()
    [Windows.Media.CompositionTarget]::remove_Rendering($onFrame)
    if ($absorb.State -eq 'running') { Stop-Absorb }
    if ($absorb.Overlay) { $absorb.Overlay.Hide() }
    $window.Hide()
}
function Show-AfterFullscreen {
    $fullscreen.Hidden=$false
    if ($absorb.Overlay) { $absorb.Overlay.Show() }
    $window.ShowActivated=$false
    $window.Show()
    [Windows.Media.CompositionTarget]::add_Rendering($onFrame)
}
if ($fullscreen.Enabled) {
    $fullscreen.Timer=[Windows.Threading.DispatcherTimer]::new()
    $fullscreen.Timer.Interval=[TimeSpan]::FromSeconds(1)
    $fullscreen.Timer.Add_Tick({
        try {
            if ([BlackHolePet.Foreground]::IsFullscreen($PID)) {
                $fullscreen.ClearChecks=0
                if (-not $fullscreen.Hidden) { Hide-ForFullscreen }
            } elseif ($fullscreen.Hidden) {
                $fullscreen.ClearChecks++
                if ($fullscreen.ClearChecks -ge 2) { Show-AfterFullscreen }
            }
        } catch { $fullscreen.Timer.Stop() }
    })
    $fullscreen.Timer.Start()
}
$window.Add_SourceInitialized({
    $source=[Windows.PresentationSource]::FromVisual($window)
    $transform=$source.CompositionTarget.TransformFromDevice
    $area=[Windows.Forms.Screen]::FromPoint($cursor).WorkingArea
    # 優先從桌面圖示的真實位置喚醒；讀不到時才用游標位置。
    $startX=[double]$cursor.X; $startY=[double]$cursor.Y
    try {
        $spot=[BlackHolePet.DesktopIcon]::Find([IO.Path]::GetFileNameWithoutExtension($shortcut))
        if ($spot) {
            $iconPixels=$absorb.IconSize*$source.CompositionTarget.TransformToDevice.M11
            $startX=$spot.X+$spot.CellX/2
            $startY=$spot.Y+4+$iconPixels/2
        }
    } catch {}
    $point=$transform.Transform([Windows.Point]::new($startX,$startY))
    $first=$transform.Transform([Windows.Point]::new($area.Left,$area.Top))
    $last=$transform.Transform([Windows.Point]::new($area.Right,$area.Bottom))
    $bounds=[Windows.Rect]::new($first,$last)
    $window.Left=[Math]::Max($bounds.Left,[Math]::Min($bounds.Right-$size,$point.X-$size/2))
    $window.Top=[Math]::Max($bounds.Top,[Math]::Min($bounds.Bottom-$size,$point.Y-$size/2))
})
$window.Add_ContentRendered({
    if ($clock.IsRunning) { return }
    if (-not $SmokeTest -and [IO.File]::Exists($shortcut)) {
        $flags=[IO.File]::GetAttributes($shortcut)
        $absorb.ShortcutFlags=[IO.FileAttributes]([int]$flags -band (-bnot [int][IO.FileAttributes]::Hidden))
        [IO.File]::SetAttributes($shortcut,($flags -bor [IO.FileAttributes]::Hidden))
    }
    $startScale=$absorb.IconSize/144
    $scale=[Windows.Media.ScaleTransform]::new($startScale,$startScale,72,72)
    $absorb.Scale=$scale
    $group=[Windows.Media.TransformGroup]::new()
    $group.Children.Add([Windows.Media.RotateTransform]::new(-12,72,72))
    $group.Children.Add($scale)
    $canvas.RenderTransform=$group
    $absorb.OriginX=$window.Left+$size/2
    $absorb.OriginY=$window.Top+$size/2
    $clock.Start()
    [Windows.Media.CompositionTarget]::add_Rendering($onFrame)
})
try { Prepare-Absorb } catch { $absorb.State='done'; $absorb.Overlay=$null }
# 不用 ShowDialog：隱藏對話框式視窗會讓它結束，全螢幕自動隱藏就會讓程式退出。
$window.Add_Closed({
    if ($fullscreen.Timer) { $fullscreen.Timer.Stop() }
    $memoryTimer.Stop()
    if ($transfer.Timer) { $transfer.Timer.Stop() }
    if ($transfer.State -ne 'idle') { End-Transfer }
    [Windows.Media.CompositionTarget]::remove_Rendering($onFrame)
    if ($absorb.Overlay) { Stop-Absorb }
    [Windows.Threading.Dispatcher]::CurrentDispatcher.InvokeShutdown()
})
# 任何未處理的錯誤：寫入記錄檔、恢復桌面圖示並關閉，不要讓圖示卡在隱藏狀態，也不留視窗在螢幕外。
[Windows.Threading.Dispatcher]::CurrentDispatcher.add_UnhandledException({
    param($sender,$e)
    $e.Handled=$true
    try { [IO.File]::AppendAllText((Join-Path $env:TEMP 'blackhole-error.log'),"$(Get-Date -Format s) $($e.Exception.ToString())`r`n`r`n") } catch {}
    try { if ($transfer.State -ne 'idle') { End-Transfer } } catch {}
    try { if ($absorb.ShortcutFlags -ne $null) { [IO.File]::SetAttributes($shortcut,$absorb.ShortcutFlags) } } catch {}
    try { $window.Close() } catch { [Windows.Threading.Dispatcher]::CurrentDispatcher.InvokeShutdown() }
})
$window.Show()
[Windows.Threading.Dispatcher]::Run()
if ($SmokeTest -and $clock.Elapsed.TotalMilliseconds -gt 280) { 'Pet rendered and animation timer ran' }
if ($SmokeTest) { "Absorb state=$($absorb.State) particles=$(if ($absorb.Items) { $absorb.Items.Count } else { 0 }) seconds=$(if ($absorb.Clock) { [Math]::Round($absorb.Clock.Elapsed.TotalSeconds,2) } else { 0 })" }

